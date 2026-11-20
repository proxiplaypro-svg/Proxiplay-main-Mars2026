// Phase 1, tranche 2a, lot 1.8 : webhook Stripe pour les abonnements de
// contrat. Evenements simules au format de l'endpoint (2026-10-28.endive),
// objets relus par un double du SDK (API 2024-06-20) : aucun reseau, aucune cle.
const {makeContractStripe} = require('./stripe_contract_fake.cjs');
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const stripeClientModule = require('../stripe_client');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const {submitMerchantSubscriptionRequestHandler} = require('../merchant_contracts_request');
const review = require('../merchant_contract_review');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');
const checkout = require('../merchant_contract_checkout');
const {adminUpdateMerchantContractsConfigHandler} = require('../merchant_contracts_config');
const {dispatchEvent} = require('../stripe_webhook');

const {db} = h;
const kUrls = {successUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=success', cancelUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=cancel'};
let sent;
let stripe;

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

/** Contrat confirme, invite, session ouverte. */
async function openSession({enseigne = 'e1'} = {}) {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: enseigne, siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  const token = /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1];
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const sessionId = Object.keys(stripe.store.sessions).at(-1);
  return {contractId, sessionId};
}

// Payloads au format endive : on n'y lit que des identifiants.
const sessionEvent = (session) => stripe.event('checkout.session.completed',
  {id: session.id, object: 'checkout.session', mode: 'subscription', subscription: session.subscription, metadata: session.metadata});
const invoiceEvent = (type, invoiceId, subscriptionId, metadata) => stripe.event(type, {id: invoiceId, object: 'invoice',
  parent: {type: 'subscription_details', subscription_details: {subscription: subscriptionId, metadata}}});
const subscriptionEvent = (type, sub) => stripe.event(type, {id: sub.id, object: 'subscription', metadata: sub.metadata});

const contract = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();
const internal = async (id) => (await db.doc(`merchant_contracts/${id}/internal/record`).get()).data();

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'merchant');
  sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
  stripe = makeContractStripe();
  stripeClientModule.getStripeClient = () => stripe;
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

test('paiement confirme : contrat actif une seule fois, miroir de l\'enseigne, liens revoques, e-mail d\'activation ; miroir V1 jamais ecrit', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  const result = await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  assert.equal(result.outcome, 'contract_activated');
  const c = await contract(contractId);
  assert.equal(c.state, 'active');
  assert.ok(c.activated_at);
  assert.equal((await internal(contractId)).billing.stripe_subscription_id, paid.subscriptionId);
  const mirror = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.equal(mirror.status, 'active');
  assert.equal(mirror.stripe_subscription_id, paid.subscriptionId);
  assert.equal(mirror.contract_id, contractId);
  assert.ok(mirror.current_period_end);
  const tokens = await db.collection('payment_tokens').where('contract_id', '==', contractId).get();
  assert.ok(tokens.docs.every((d) => d.data().revoked_at), 'le lien ne peut plus servir');
  assert.equal((await db.collection('merchant_subscriptions').get()).size, 0, 'miroir V1 intact');
  const activation = sent.filter((m) => /abonnement est actif/.test(m.subject));
  assert.equal(activation.length, 1);
  assert.match(activation[0].text, /point de départ de la période annuelle \(CGV, art\. 8\.2\)/);
  // Le meme paiement annonce par invoice.paid (creation) : rien de plus.
  const again = await dispatchEvent(db, invoiceEvent('invoice.paid', paid.invoiceId, paid.subscriptionId, stripe.store.subscriptions[paid.subscriptionId].metadata));
  assert.equal(again.outcome, 'contract_already_active');
  assert.equal(sent.filter((m) => /abonnement est actif/.test(m.subject)).length, 1);
});

test('invoice.paid avant checkout.session.completed : activation par le premier, idempotence ensuite', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  const meta = stripe.store.subscriptions[paid.subscriptionId].metadata;
  assert.equal((await dispatchEvent(db, invoiceEvent('invoice.paid', paid.invoiceId, paid.subscriptionId, meta))).outcome, 'contract_activated');
  assert.equal((await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]))).outcome, 'contract_already_active');
  assert.equal((await contract(contractId)).state, 'active');
});

test('paiement recu apres cloture : jamais de reactivation, remboursement integral, annulation, e-mail et alerte', async () => {
  const {contractId, sessionId} = await openSession();
  await db.doc(`merchant_contracts/${contractId}`).update({state: 'closed_unpaid'});
  const paid = stripe.complete(sessionId);
  const result = await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  assert.equal(result.outcome, 'contract_late_payment_refunded');
  assert.equal((await contract(contractId)).state, 'closed_unpaid');
  assert.equal(stripe.calls.refundsCreate.length, 1);
  assert.equal(stripe.calls.refundsCreate[0].params.payment_intent, stripe.store.invoices[paid.invoiceId].payment_intent);
  assert.equal(stripe.calls.refundsCreate[0].options.idempotencyKey, `refund-${paid.invoiceId}`);
  assert.deepEqual(stripe.calls.subscriptionsCancel.map((c) => [c.subscriptionId, c.params]), [[paid.subscriptionId, {prorate: false, invoice_now: false}]]);
  assert.ok(sent.some((m) => /paiement remboursé/.test(m.subject)));
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'paiement_tardif_rembourse').get()).size, 1);
  assert.equal((await internal(contractId)).refunds.length, 1);
  // Rejeu du meme evenement : aucun second remboursement (cles d'idempotence).
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  assert.equal(new Set(stripe.calls.refundsCreate.map((c) => c.options.idempotencyKey)).size, 1);
});

test('paiement en delai de retractation, apres retractation, refus ou fin : rembourse, contrat inchange', async () => {
  for (const state of ['withdrawal_pending', 'withdrawn', 'refused', 'ended']) {
    await h.clearFirestore();
    await h.setConfig();
    await h.seedMerchant('merchant');
    await h.seedAdmin('admin');
    await h.seedEnseigne('e1', 'merchant');
    const {contractId, sessionId} = await openSession();
    await db.doc(`merchant_contracts/${contractId}`).update({state});
    const before = stripe.calls.refundsCreate.length;
    stripe.complete(sessionId);
    const result = await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
    assert.equal(result.outcome, 'contract_late_payment_refunded', state);
    assert.equal(stripe.calls.refundsCreate.length, before + 1, state);
    assert.equal((await contract(contractId)).state, state);
  }
});

/** Paiement non rattachable : aucun appel Stripe qui deplace de l'argent, trace et alerte une seule fois. */
async function assertNoMoneyTraced(event, {reason, contractId}) {
  const result = await dispatchEvent(db, event);
  assert.equal(result.outcome, 'unmatched_contract_payment');
  assert.equal(result.reason, reason);
  assert.equal(stripe.calls.refundsCreate.length, 0);
  assert.equal(stripe.calls.creditNotesCreate.length, 0);
  assert.equal(stripe.calls.subscriptionsCancel.length, 0);
  assert.equal(stripe.calls.invoicesVoid.length, 0);
  const trace = (await db.doc(`stripe_unmatched_events/${event.id}`).get()).data();
  assert.equal(trace.reason, reason);
  assert.equal(trace.contract_id, contractId);
  assert.equal(trace.event_type, event.type);
  assert.equal(trace.resolved, false);
  // Rejeu : ni seconde trace ni seconde alerte, toujours aucun argent.
  await dispatchEvent(db, event);
  assert.equal(stripe.calls.refundsCreate.length + stripe.calls.subscriptionsCancel.length, 0);
  assert.equal((await db.collection('stripe_unmatched_events').get()).size, 1);
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'stripe_evenement_non_rattache').get()).size, 1);
  assert.equal(sent.filter((m) => /paiement remboursé/.test(m.subject)).length, 0, 'aucun e-mail de remboursement au commercant');
}

test('contrat inconnu : aucune action sur l\'argent, trace et alerte', async () => {
  const {contractId, sessionId} = await openSession();
  stripe.complete(sessionId);
  await db.doc(`merchant_contracts/${contractId}`).delete();
  await assertNoMoneyTraced(sessionEvent(stripe.store.sessions[sessionId]), {reason: 'contrat_inconnu', contractId});
});

test('enseigne differente : aucune action sur l\'argent, contrat non active, trace et alerte', async () => {
  const {contractId, sessionId} = await openSession();
  stripe.complete(sessionId);
  await db.doc(`merchant_contracts/${contractId}`).update({enseigne_id: 'e2'});
  await assertNoMoneyTraced(sessionEvent(stripe.store.sessions[sessionId]), {reason: 'enseigne_differente', contractId});
  assert.equal((await contract(contractId)).state, 'payment_invited');
  assert.equal(Object.keys((await internal(contractId)).unmatched_payments).length, 1);
  assert.equal((await internal(contractId)).billing, undefined);
});

test('etats submitted et confirmed : aucune action sur l\'argent, etat inchange, trace et alerte', async () => {
  for (const state of ['submitted', 'confirmed']) {
    await h.clearFirestore();
    await h.setConfig();
    await h.seedMerchant('merchant');
    await h.seedAdmin('admin');
    await h.seedEnseigne('e1', 'merchant');
    stripe.calls.refundsCreate.length = 0;
    stripe.calls.subscriptionsCancel.length = 0;
    sent.length = 0;
    const {contractId, sessionId} = await openSession();
    await db.doc(`merchant_contracts/${contractId}`).update({state});
    stripe.complete(sessionId);
    await assertNoMoneyTraced(sessionEvent(stripe.store.sessions[sessionId]), {reason: `etat_${state}`, contractId});
    assert.equal((await contract(contractId)).state, state);
  }
});

test('second paiement pour un contrat deja actif : le second abonnement est rembourse et annule', async () => {
  const {contractId, sessionId} = await openSession();
  const first = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  // Seconde session payee (ex. deux onglets) : nouvel abonnement.
  const secondSession = await stripe.checkout.sessions.create({...stripe.store.sessions[sessionId]._params}, {idempotencyKey: 'autre'});
  const second = stripe.complete(secondSession.id);
  const result = await dispatchEvent(db, sessionEvent(stripe.store.sessions[secondSession.id]));
  assert.equal(result.outcome, 'contract_late_payment_refunded');
  assert.equal((await internal(contractId)).billing.stripe_subscription_id, first.subscriptionId);
  assert.deepEqual(stripe.calls.subscriptionsCancel.map((c) => c.subscriptionId), [second.subscriptionId]);
  assert.equal((await contract(contractId)).state, 'active');
});

test('option des avoirs activee : avoir au lieu d\'un simple remboursement', async () => {
  await adminUpdateMerchantContractsConfigHandler({creditNotesEnabled: true}, h.adminContext());
  const {contractId, sessionId} = await openSession();
  await db.doc(`merchant_contracts/${contractId}`).update({state: 'closed_unpaid'});
  const paid = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  assert.equal(stripe.calls.refundsCreate.length, 0);
  assert.equal(stripe.calls.creditNotesCreate.length, 1);
  assert.equal(stripe.calls.creditNotesCreate[0].params.invoice, paid.invoiceId);
  assert.equal(stripe.calls.creditNotesCreate[0].params.refund_amount, paid.total);
});

test('renouvellement : echec -> delai de grace de 15 jours et une seule notification ; paiement -> regularise', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  const sub = stripe.store.subscriptions[paid.subscriptionId];
  sub.status = 'past_due';
  stripe.store.invoices.in_renewal = {id: 'in_renewal', subscription: sub.id, billing_reason: 'subscription_cycle', status: 'open',
    paid: false, amount_due: 43800, hosted_invoice_url: 'https://invoice.stripe.com/i/test_renewal', livemode: false};
  sent.length = 0;
  const before = Date.now();
  const failed = await dispatchEvent(db, invoiceEvent('invoice.payment_failed', 'in_renewal', sub.id, sub.metadata));
  assert.equal(failed.outcome, 'contract_renewal_failed_notified');
  const mirror = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.equal(mirror.status, 'past_due');
  const grace = mirror.grace_until.toMillis();
  assert.ok(grace >= before + 15 * 86400000 - 5000 && grace <= Date.now() + 15 * 86400000 + 5000, 'quinze jours (art. 11)');
  assert.equal(mirror.unpaid_invoice_url, 'https://invoice.stripe.com/i/test_renewal');
  assert.equal(sent.length, 1);
  assert.match(sent[0].text, /délai de régularisation de quinze jours/);
  assert.match(sent[0].text, /aucune pénalité n'est réclamée \(art\. 9\)/);
  // Nouvelle tentative Stripe en echec : pas de seconde notification immediate.
  await dispatchEvent(db, invoiceEvent('invoice.payment_failed', 'in_renewal', sub.id, sub.metadata));
  assert.equal(sent.length, 1);
  assert.equal((await db.doc('enseigne_subscriptions/e1').get()).data().grace_until.toMillis(), grace, 'jamais repousse');
  // Regularisation.
  sub.status = 'active';
  Object.assign(stripe.store.invoices.in_renewal, {status: 'paid', paid: true, status_transitions: {paid_at: Math.floor(Date.now() / 1000)}});
  await dispatchEvent(db, invoiceEvent('invoice.paid', 'in_renewal', sub.id, sub.metadata));
  const after = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.equal(after.grace_until, null);
  assert.equal(after.unpaid_invoice_url, null);
  assert.ok(after.last_renewal_paid_at);
  assert.equal((await contract(contractId)).state, 'active');
});

test('abonnement mis a jour puis supprime : miroir, puis fin du contrat', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  const sub = stripe.store.subscriptions[paid.subscriptionId];
  sub.cancel_at_period_end = true;
  await dispatchEvent(db, subscriptionEvent('customer.subscription.updated', sub));
  assert.equal((await db.doc('enseigne_subscriptions/e1').get()).data().cancel_at_period_end, true);
  Object.assign(sub, {status: 'canceled', ended_at: Math.floor(Date.now() / 1000)});
  await dispatchEvent(db, subscriptionEvent('customer.subscription.deleted', sub));
  const c = await contract(contractId);
  assert.equal(c.state, 'ended');
  assert.equal(c.end_reason, 'stripe_canceled');
  assert.equal((await db.collection('merchant_subscriptions').get()).size, 0);
});

test('remboursement et litige sur un abonnement de contrat : traces, alerte en cas de litige, parrainage V1 non touche', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  const refunded = await dispatchEvent(db, stripe.event('charge.refunded', {id: paid.chargeId, object: 'charge'}));
  assert.equal(refunded.outcome, 'contract_refund_recorded');
  stripe.store.charges[paid.chargeId].invoice = paid.invoiceId;
  const dispute = await dispatchEvent(db, stripe.event('charge.dispute.created', {id: 'dp_1', object: 'dispute', charge: paid.chargeId}));
  assert.equal(dispute.outcome, 'contract_dispute_recorded');
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'litige_paiement').get()).size, 1);
  assert.equal((await internal(contractId)).charge_events.length, 2);
  assert.equal((await db.collection('merchant_referrals').get()).size, 0);
});

test('evenements d\'abonnement de contrat non rattachables (contrat inconnu, autre enseigne) : trace et alerte, aucun argent', async () => {
  const {contractId, sessionId} = await openSession();
  const paid = stripe.complete(sessionId);
  await dispatchEvent(db, sessionEvent(stripe.store.sessions[sessionId]));
  const sub = stripe.store.subscriptions[paid.subscriptionId];
  sub.metadata = {...sub.metadata, enseigneId: 'e2'};
  const mismatch = await dispatchEvent(db, subscriptionEvent('customer.subscription.updated', sub));
  assert.equal(mismatch.outcome, 'ignored_enseigne_mismatch');
  sub.metadata = {...sub.metadata, enseigneId: 'e1', contractId: 'contrat_inexistant'};
  const unknownEvent = subscriptionEvent('customer.subscription.updated', sub);
  const unknown = await dispatchEvent(db, unknownEvent);
  assert.equal(unknown.outcome, 'contract_unknown');
  const trace = (await db.doc(`stripe_unmatched_events/${unknownEvent.id}`).get()).data();
  assert.equal(trace.contract_id, 'contrat_inexistant');
  assert.equal(trace.subscription_id, paid.subscriptionId);
  const traces = (await db.collection('stripe_unmatched_events').get()).docs.map((d) => d.data().outcome).sort();
  assert.deepEqual(traces, ['contract_unknown', 'ignored_enseigne_mismatch']);
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'stripe_evenement_non_rattache').get()).size, 2);
  assert.equal(stripe.calls.refundsCreate.length + stripe.calls.subscriptionsCancel.length + stripe.calls.creditNotesCreate.length, 0);
  assert.equal((await contract(contractId)).state, 'active');
});

test('session de contrat expiree : rien dans le miroir V1', async () => {
  const {sessionId} = await openSession();
  const session = stripe.store.sessions[sessionId];
  const result = await dispatchEvent(db, stripe.event('checkout.session.expired',
    {id: session.id, object: 'checkout.session', client_reference_id: session.client_reference_id, metadata: session.metadata}));
  assert.equal(result.outcome, 'contract_checkout_expired');
  assert.equal((await db.collection('merchant_subscriptions').get()).size, 0);
});

test('session non payee (statut relu chez Stripe) : aucune activation', async () => {
  const {contractId, sessionId} = await openSession();
  stripe.complete(sessionId);
  stripe.store.sessions[sessionId].payment_status = 'unpaid';
  const result = await dispatchEvent(db, sessionEvent({...stripe.store.sessions[sessionId], payment_status: 'paid'}));
  assert.equal(result.outcome, 'contract_checkout_unpaid', 'le payload annonce paye, l\'objet relu dit non : on suit l\'objet relu');
  assert.equal((await contract(contractId)).state, 'payment_invited');
});
