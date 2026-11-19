// Phase 1, tranche 2a, lot 1.5 : retractation (art. 7). Double du SDK Stripe.
const {makeContractStripe} = require('./stripe_contract_fake.cjs');
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const stripeClientModule = require('../stripe_client');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const paris = require('../paris_time');
const {submitMerchantSubscriptionRequestHandler} = require('../merchant_contracts_request');
const review = require('../merchant_contract_review');
const origin = require('../merchant_contract_origin');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');
const checkout = require('../merchant_contract_checkout');
const payment = require('../merchant_contract_payment');
const withdrawal = require('../merchant_contract_withdrawal');
const {dispatchEvent} = require('../stripe_webhook');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
const kUrls = {successUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=success', cancelUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=cancel'};
let sent;
let stripe;

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

async function confirmed(overrides = {}, {enseigne = 'e1'} = {}) {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: enseigne, siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true, ...overrides,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  return contractId;
}

const contract = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();
const internal = async (id) => (await db.doc(`merchant_contracts/${id}/internal/record`).get()).data();

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
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

test('« Me rétracter » pendant le delai : withdrawn, accuse de reception immediat, rien a payer, aucun appel Stripe', async () => {
  const contractId = await confirmed({visitDeclared: true});
  sent.length = 0;
  const result = await withdrawal.withdrawMerchantContractHandler({contractId}, h.merchantContext());
  assert.deepEqual(result, {state: 'withdrawn', already: false, refunded: 0});
  const c = await contract(contractId);
  assert.equal(c.state, 'withdrawn');
  assert.ok(c.withdrawn_at);
  const i = await internal(contractId);
  assert.equal(i.withdrawal.channel, 'online');
  assert.equal(i.withdrawal.state_before, 'withdrawal_pending');
  assert.deepEqual(sent.map((m) => m.to), ['merchant@example.test', 'alertes@proxiplay.test']);
  assert.match(sent[0].subject, /accusé de réception de votre rétractation/);
  assert.match(sent[0].text, /Aucune somme n'est due \(art\. 7\.5\)/);
  assert.equal(stripe.calls.refundsCreate.length + stripe.calls.sessionsExpire.length + stripe.calls.subscriptionsCancel.length, 0);
  // Idempotent : aucun second accuse.
  assert.equal((await withdrawal.withdrawMerchantContractHandler({contractId}, h.merchantContext())).already, true);
  assert.equal(sent.length, 2);
});

test('limites : souscription spontanee, delai expire, contrat d\'un autre compte', async () => {
  const spontaneous = await confirmed();
  await h.rejectsWith(withdrawal.withdrawMerchantContractHandler({contractId: spontaneous}, h.merchantContext()), 'not_demarchee');
  const late = await confirmed({visitDeclared: true}, {enseigne: 'e2'});
  await db.doc(`merchant_contracts/${late}`).update({withdrawal_deadline: Timestamp.fromMillis(Date.now() - 1000)});
  await h.rejectsWith(withdrawal.withdrawMerchantContractHandler({contractId: late}, h.merchantContext()), 'withdrawal_deadline_passed');
  await h.rejectsWith(withdrawal.withdrawMerchantContractHandler({contractId: late}, h.merchantContext('other')), 'contract_not_found');
  assert.equal((await contract(late)).state, 'withdrawal_pending');
});

test('e-mail ou courrier saisi par l\'admin : la date d\'envoi fait foi, meme recu apres le delai', async () => {
  const contractId = await confirmed({visitDeclared: true});
  // Fin du delai il y a cinq jours (passe), pour une reception posterieure au delai.
  const deadline = paris.endOfParisDay(paris.parisDate(Date.now() - 5 * 86400000));
  const lastDay = paris.parisDate(deadline);
  const lastDayText = `${lastDay.y}-${String(lastDay.m).padStart(2, '0')}-${String(lastDay.d).padStart(2, '0')}`;
  // Lettre postee le dernier jour, recue trois jours plus tard.
  await db.doc(`merchant_contracts/${contractId}`).update({withdrawal_deadline: Timestamp.fromMillis(deadline)});
  const result = await withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'courrier', sentAt: lastDayText,
    reference: 'Lettre RAR 1A234', receivedAt: new Date(deadline + 3 * 86400000).toISOString()}, h.adminContext());
  assert.equal(result.state, 'withdrawn');
  const i = await internal(contractId);
  assert.equal(i.withdrawal.channel, 'courrier');
  assert.equal(i.withdrawal.reference, 'Lettre RAR 1A234');
  assert.equal(i.withdrawal.sent_at.toMillis(), paris.parisLocalToUtc(lastDay.y, lastDay.m, lastDay.d, 12));
  assert.ok(i.withdrawal.received_at.toMillis() > deadline);
});

test('saisie admin : envoi apres le delai refuse, sauf prolongation legale motivee (L221-20) ; reference requise ; admin seul', async () => {
  const contractId = await confirmed({visitDeclared: true});
  await db.doc(`merchant_contracts/${contractId}`).update({withdrawal_deadline: Timestamp.fromMillis(Date.now() - 2 * 86400000)});
  const sentAt = new Date().toISOString();
  await h.rejectsWith(withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'email', sentAt, reference: 'Mail du jour'}, h.adminContext()),
    'withdrawal_deadline_passed');
  await h.rejectsWith(withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'email', sentAt}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'fax', sentAt, reference: 'x'}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'email', sentAt: '2999-01-01', reference: 'x'}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'email', sentAt, reference: 'x'}, h.merchantContext()), 'permission-denied');
  const result = await withdrawal.adminRecordWithdrawalHandler({contractId, channel: 'email', sentAt, reference: 'Mail du jour',
    lateReason: 'Formulaire de rétractation non remis lors de la visite : délai prolongé (L221-20)'}, h.adminContext());
  assert.equal(result.state, 'withdrawn');
  assert.match((await internal(contractId)).withdrawal.late_reason, /L221-20/);
});

test('visite signalee apres paiement puis retractation : remboursement integral, annulation, contrat retracte', async () => {
  const contractId = await confirmed();
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  const token = /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1];
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const sessionId = Object.keys(stripe.store.sessions)[0];
  const paid = stripe.complete(sessionId);
  const session = stripe.store.sessions[sessionId];
  await dispatchEvent(db, stripe.event('checkout.session.completed', {id: session.id, object: 'checkout.session', mode: 'subscription',
    subscription: session.subscription, metadata: session.metadata}));
  assert.equal((await contract(contractId)).state, 'active');
  await origin.reportMerchantVisitHandler({contractId}, h.merchantContext());
  assert.equal((await contract(contractId)).state, 'active', 'paye : reste actif, le droit de retractation s\'ouvre');
  sent.length = 0;
  const result = await withdrawal.withdrawMerchantContractHandler({contractId}, h.merchantContext());
  assert.equal(result.refunded, 1);
  assert.equal(stripe.calls.refundsCreate.length, 1);
  assert.equal(stripe.calls.refundsCreate[0].params.payment_intent, stripe.store.invoices[paid.invoiceId].payment_intent);
  assert.deepEqual(stripe.calls.subscriptionsCancel.map((c) => c.subscriptionId), [paid.subscriptionId]);
  assert.equal((await contract(contractId)).state, 'withdrawn');
  assert.match(sent[0].text, /vous est remboursée intégralement et l'abonnement est annulé/);
  assert.match(sent[0].text, /438,00 €/);
  // L'annulation annoncee ensuite par Stripe ne change pas l'etat (pas de « ended »).
  await dispatchEvent(db, stripe.event('customer.subscription.deleted', {id: paid.subscriptionId, object: 'subscription',
    metadata: stripe.store.subscriptions[paid.subscriptionId].metadata}));
  assert.equal((await contract(contractId)).state, 'withdrawn');
});

test('retractation pendant l\'attente du paiement (visite signalee) : session et liens fermes, aucun paiement possible', async () => {
  const contractId = await confirmed();
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  const token = /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1];
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  await origin.reportMerchantVisitHandler({contractId}, h.merchantContext());
  assert.equal(stripe.calls.sessionsExpire.length, 1, 'session expiree au signalement');
  await withdrawal.withdrawMerchantContractHandler({contractId}, h.merchantContext());
  assert.equal((await contract(contractId)).state, 'withdrawn');
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext()), 'not_payment_invited');
});

test('effet Stripe en echec : retractation acquise, alerte admin pour action manuelle', async () => {
  const contractId = await confirmed();
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  const token = /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1];
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const sessionId = Object.keys(stripe.store.sessions)[0];
  stripe.complete(sessionId);
  const session = stripe.store.sessions[sessionId];
  await dispatchEvent(db, stripe.event('checkout.session.completed', {id: session.id, object: 'checkout.session', mode: 'subscription',
    subscription: session.subscription, metadata: session.metadata}));
  await origin.reportMerchantVisitHandler({contractId}, h.merchantContext());
  stripe.refunds.create = async () => {
    throw new Error('Stripe indisponible (test)');
  };
  await withdrawal.withdrawMerchantContractHandler({contractId}, h.merchantContext());
  assert.equal((await contract(contractId)).state, 'withdrawn');
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'retractation_stripe_echec').get()).size, 1);
});
