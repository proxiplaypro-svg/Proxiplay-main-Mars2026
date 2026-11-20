// Phase 1, tranche 2b, lot 1.12 : fins de contrat. Contrats actives par le
// parcours reel (demande, confirmation, Checkout, webhook) ; Stripe remplace
// par un double du SDK (aucun reseau, aucune cle).
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
const end = require('../merchant_contract_end');
const schedule = require('../merchant_contract_schedule');

const {db} = h;
const {Timestamp} = h.admin.firestore;
const kUrls = {successUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=success', cancelUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=cancel'};
const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));
const kDay = 86400000;
let sent;
let stripe;

/** Contrat spontane actif, par le parcours complet. */
async function activeContract() {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  const token = /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1];
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const sessionId = Object.keys(stripe.store.sessions).at(-1);
  const paid = stripe.complete(sessionId);
  const session = stripe.store.sessions[sessionId];
  await dispatchEvent(db, stripe.event('checkout.session.completed', {id: session.id, object: 'checkout.session', mode: 'subscription',
    subscription: session.subscription, metadata: session.metadata}));
  assert.equal((await contract(contractId)).state, 'active');
  sent.length = 0;
  return {contractId, ...paid, sub: stripe.store.subscriptions[paid.subscriptionId]};
}

/** Place l'echeance dans le passe pour que le renouvellement soit deja arrive. */
function renewalInThePast(sub, daysAgo = 5) {
  const nowSec = Math.floor(Date.now() / 1000);
  sub.current_period_start = nowSec - (365 - daysAgo) * 86400 - 3600;
  sub.current_period_end = nowSec - daysAgo * 86400;
}

const contract = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();
const internal = async (id) => (await db.doc(`merchant_contracts/${id}/internal/record`).get()).data();
const moneyCalls = () => stripe.calls.refundsCreate.length + stripe.calls.creditNotesCreate.length;
const disable = (contractId, uid = 'merchant') => end.disableMerchantRenewalHandler({contractId}, h.merchantContext(uid));

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
  stripe = makeContractStripe();
  stripeClientModule.getStripeClient = () => stripe;
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

// --- Art. 9 : desactivation -------------------------------------------------------

test('desactivation avant l\'echeance : fin de periode, rien d\'annule ni rembourse, e-mail de confirmation, idempotente', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  const result = await disable(contractId);
  assert.equal(result.outcome, 'disabled_at_period_end');
  assert.equal(result.endsAt, sub.current_period_end * 1000);
  assert.deepEqual(stripe.calls.subscriptionsUpdate.map((c) => [c.subscriptionId, c.params]), [[subscriptionId, {cancel_at_period_end: true}]]);
  assert.equal(stripe.calls.invoicesVoid.length + stripe.calls.subscriptionsCancel.length + moneyCalls(), 0);
  assert.equal((await contract(contractId)).state, 'active', 'service jusqu\'a la fin de la periode payee');
  const mirror = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.equal(mirror.cancel_at_period_end, true);
  assert.ok(mirror.renewal_disabled_at);
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /renouvellement désactivé/);
  assert.match(sent[0].text, /prestations restent accessibles/);
  const again = await disable(contractId);
  assert.equal(again.outcome, 'already_disabled');
  assert.equal(stripe.calls.subscriptionsUpdate.length, 1);
  assert.equal(sent.length, 1);
  // A l'echeance, Stripe annule : le webhook termine le contrat avec le motif non_renewal.
  Object.assign(sub, {status: 'canceled', ended_at: sub.current_period_end});
  await dispatchEvent(db, stripe.event('customer.subscription.deleted', {id: sub.id, object: 'subscription'}));
  const c = await contract(contractId);
  assert.equal(c.state, 'ended');
  assert.equal(c.end_reason, 'non_renewal');
});

test('desactivation dans l\'heure du renouvellement (brouillon) : auto_advance=false, finalisation, void, annulation', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 0);
  const invoiceId = stripe.renew(subscriptionId, {status: 'draft'});
  const result = await disable(contractId);
  assert.equal(result.outcome, 'ended_at_renewal');
  assert.equal(result.invoiceStatus, 'void');
  assert.deepEqual(stripe.calls.invoicesUpdate.map((c) => [c.invoiceId, c.params]), [[invoiceId, {auto_advance: false}]]);
  assert.deepEqual(stripe.calls.invoicesFinalize.map((c) => [c.invoiceId, c.params]), [[invoiceId, {auto_advance: false}]]);
  assert.deepEqual(stripe.calls.invoicesVoid, [invoiceId]);
  assert.deepEqual(stripe.calls.subscriptionsCancel.map((c) => [c.subscriptionId, c.params]), [[subscriptionId, {prorate: false, invoice_now: false}]]);
  assert.equal(moneyCalls(), 0);
  const c = await contract(contractId);
  assert.equal(c.state, 'ended');
  assert.equal(c.end_reason, 'non_renewal');
  assert.match(sent[0].text, /Aucune somme n'est prélevée pour le renouvellement/);
});

test('course : prelevement passe entre la finalisation et le void (code d\'erreur vide) -> statut relu, remboursement integral', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 0);
  const invoiceId = stripe.renew(subscriptionId, {status: 'draft'});
  stripe.hooks.afterFinalize = (invoice) => Object.assign(invoice, {status: 'paid', paid: true, amount_paid: 43800,
    status_transitions: {paid_at: Math.floor(Date.now() / 1000)}});
  const result = await disable(contractId);
  assert.equal(result.invoiceStatus, 'paid');
  assert.equal(result.refunded, 1);
  assert.deepEqual(stripe.calls.invoicesVoid, [], 'facture relue payee : aucun void tente');
  assert.equal(stripe.calls.refundsCreate.length, 1);
  assert.equal(stripe.calls.refundsCreate[0].params.payment_intent, stripe.store.invoices[invoiceId].payment_intent);
  assert.equal(stripe.calls.refundsCreate[0].params.amount, undefined, 'integral');
  assert.equal(stripe.calls.subscriptionsCancel.length, 1);
  assert.equal((await contract(contractId)).state, 'ended');
  assert.match(sent[0].text, /vous est remboursé intégralement \(438,00 €\)/);
  assert.equal((await internal(contractId)).end.invoice_status_final, 'paid');
});

test('course au moment du void : refus a code vide, statut relu paye -> remboursement ; option avoirs : avoir', async () => {
  await adminUpdateMerchantContractsConfigHandler({creditNotesEnabled: true}, h.adminContext());
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 0);
  const invoiceId = stripe.renew(subscriptionId, {status: 'open'});
  stripe.hooks.beforeVoid = (invoice) => Object.assign(invoice, {status: 'paid', paid: true, amount_paid: 43800});
  const result = await disable(contractId);
  assert.equal(result.invoiceStatus, 'paid');
  assert.deepEqual(stripe.calls.invoicesVoid, [invoiceId], 'void tente puis refuse');
  assert.equal(stripe.calls.refundsCreate.length, 0);
  assert.deepEqual(stripe.calls.creditNotesCreate.map((c) => [c.params.invoice, c.params.amount, c.params.refund_amount]),
    [[invoiceId, 43800, 43800]]);
  assert.equal(stripe.calls.subscriptionsCancel.length, 1);
});

test('desactivation pendant le delai de regularisation : void, annulation, aucune penalite, motif deactivated_during_grace', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 3);
  const invoiceId = stripe.renew(subscriptionId, {status: 'open'});
  const result = await disable(contractId);
  assert.equal(result.outcome, 'ended_during_grace');
  assert.deepEqual(stripe.calls.invoicesFinalize, [], 'deja finalisee');
  assert.deepEqual(stripe.calls.invoicesVoid, [invoiceId]);
  assert.equal(stripe.store.invoices[invoiceId].status, 'void');
  assert.equal(moneyCalls(), 0);
  const c = await contract(contractId);
  assert.equal(c.end_reason, 'deactivated_during_grace');
  assert.match(sent[0].text, /aucune pénalité n'est réclamée/);
});

test('void sans effet (facture toujours ouverte) : rien n\'est annule, alerte admin, erreur au commercant', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 3);
  stripe.renew(subscriptionId, {status: 'open'});
  stripe.hooks.beforeVoid = () => {
    throw Object.assign(new Error('Stripe indisponible'), {type: 'StripeAPIError', code: null});
  };
  await h.rejectsWith(disable(contractId), 'invoice_not_settled');
  assert.equal(stripe.calls.subscriptionsCancel.length, 0);
  assert.equal(moneyCalls(), 0);
  assert.equal((await contract(contractId)).state, 'active');
  assert.equal((await db.collection('admin_alerts').where('kind', '==', 'desactivation_echec').get()).size, 1);
  assert.equal((await internal(contractId)).end_lock_at, undefined, 'verrou libere');
});

test('desactivation : autre compte, contrat non actif, interrupteur coupe', async () => {
  const {contractId} = await activeContract();
  await h.rejectsWith(disable(contractId, 'other'), 'contract_not_found');
  await h.setConfig({enabled: false});
  await h.rejectsWith(disable(contractId), 'contracts_disabled');
  await h.setConfig();
  await db.doc(`merchant_contracts/${contractId}`).update({state: 'ended'});
  await h.rejectsWith(disable(contractId), 'not_active');
  assert.equal(stripe.calls.subscriptionsUpdate.length + stripe.calls.subscriptionsCancel.length + moneyCalls(), 0);
});

// --- Art. 9 : rappel des 45 jours manque ---------------------------------------------

async function paidRenewal() {
  const ctx = await activeContract();
  renewalInThePast(ctx.sub, 5);
  const renewalMs = ctx.sub.current_period_end * 1000;
  const invoiceId = stripe.renew(ctx.subscriptionId, {status: 'paid'});
  stripe.store.invoices[invoiceId].status_transitions = {paid_at: Math.floor(renewalMs / 1000) + 3600};
  return {...ctx, invoiceId, renewalMs};
}

const refundRenewal = (contractId, invoiceId, extra = {}) => end.adminRefundRenewalHandler({contractId, invoiceId,
  requestedAt: new Date().toISOString().slice(0, 10), reference: 'E-mail du commerçant du jour', ...extra}, h.adminContext());

test('rappel J-45 marque missed : remboursement integral du renouvellement, annulation, motif renewal_refunded', async () => {
  const {contractId, subscriptionId, invoiceId, renewalMs} = await paidRenewal();
  await db.doc(`renewal_reminders/${schedule.reminderDocId(subscriptionId, renewalMs)}`).set({j45: {missed: true}});
  const result = await refundRenewal(contractId, invoiceId);
  assert.equal(result.refundedCents, 43800);
  assert.equal(stripe.calls.refundsCreate.length, 1);
  assert.equal(stripe.calls.refundsCreate[0].options.idempotencyKey, `refund-${invoiceId}-art9`);
  assert.equal(stripe.calls.refundsCreate[0].params.payment_intent, stripe.store.invoices[invoiceId].payment_intent, 'seule la facture du renouvellement');
  assert.equal(stripe.calls.subscriptionsCancel.length, 1);
  const c = await contract(contractId);
  assert.equal(c.state, 'ended');
  assert.equal(c.end_reason, 'renewal_refunded');
  assert.match(sent[0].text, /ne vous avait pas été envoyé \(CGV art\. 9\)/);
});

test('rappel J-45 sans aucune trace d\'envoi a temps : missed ; envoye a temps : refus, aucun argent', async () => {
  const ctx = await paidRenewal();
  // Aucune trace : remboursement possible.
  assert.equal(await end.renewalReminderMissed(db, {contractId: ctx.contractId, subscriptionId: ctx.subscriptionId,
    renewalMs: ctx.renewalMs, internal: {}}), true);
  // Envoye a temps (trace d'e-mail avant l'echeance du rappel) : refus.
  const key = schedule.renewalReminderKey(45, ctx.renewalMs);
  await db.doc(`merchant_contracts/${ctx.contractId}/internal/record`).set({emails: {[key]: {
    sent_at: Timestamp.fromMillis(ctx.renewalMs - 46 * kDay)}}}, {merge: true});
  await h.rejectsWith(refundRenewal(ctx.contractId, ctx.invoiceId), 'reminder_not_missed');
  await db.doc(`renewal_reminders/${schedule.reminderDocId(ctx.subscriptionId, ctx.renewalMs)}`).set({j45: {missed: false}});
  await h.rejectsWith(refundRenewal(ctx.contractId, ctx.invoiceId), 'reminder_not_missed');
  assert.equal(moneyCalls() + stripe.calls.subscriptionsCancel.length, 0);
  assert.equal((await contract(ctx.contractId)).state, 'active');
});

test('remboursement art. 9 : demande hors des 30 jours, facture initiale, reference absente : refus', async () => {
  const ctx = await paidRenewal();
  await db.doc(`renewal_reminders/${schedule.reminderDocId(ctx.subscriptionId, ctx.renewalMs)}`).set({j45: {missed: true}});
  stripe.store.invoices[ctx.invoiceId].status_transitions = {paid_at: Math.floor((Date.now() - 40 * kDay) / 1000)};
  await h.rejectsWith(refundRenewal(ctx.contractId, ctx.invoiceId), 'refund_request_out_of_time');
  await h.rejectsWith(refundRenewal(ctx.contractId, ctx.invoiceId_initial || Object.keys(stripe.store.invoices)[0]), 'invoice_mismatch');
  await h.rejectsWith(refundRenewal(ctx.contractId, ctx.invoiceId, {reference: ''}), 'invalid_field');
  await h.rejectsWith(end.adminRefundRenewalHandler({contractId: ctx.contractId, invoiceId: ctx.invoiceId, requestedAt: '2027-01-01',
    reference: 'x'}, h.merchantContext()), 'permission-denied');
  assert.equal(moneyCalls() + stripe.calls.subscriptionsCancel.length, 0);
});

// --- Art. 10, 11, 18, 23 -------------------------------------------------------------------

const endContract = (contractId, data) => end.adminEndContractHandler({contractId, detail: 'Exposé des faits', ...data}, h.adminContext());

test('art. 10 : remboursement fixe par l\'admin, jamais au-dela du paye ; annulation, motif provider_breach', async () => {
  const {contractId, invoiceId} = await activeContract();
  await h.rejectsWith(endContract(contractId, {reason: 'provider_breach', refundCents: 43801}), 'refund_above_paid');
  assert.equal(moneyCalls() + stripe.calls.subscriptionsCancel.length, 0, 'controle avant toute action Stripe');
  assert.equal((await internal(contractId)).pending_end_reason, undefined);
  const result = await endContract(contractId, {reason: 'provider_breach', refundCents: 10000});
  assert.equal(result.refundedCents, 10000);
  assert.deepEqual(stripe.calls.refundsCreate.map((c) => [c.params.payment_intent, c.params.amount, c.options.idempotencyKey]),
    [[stripe.store.invoices[invoiceId].payment_intent, 10000, `refund-${invoiceId}-provider_breach`]]);
  assert.equal(stripe.calls.subscriptionsCancel.length, 1);
  const c = await contract(contractId);
  assert.equal(c.end_reason, 'provider_breach');
  assert.match(sent[0].text, /manquement de ProxiPlay \(CGV art\. 10\)/);
  assert.match(sent[0].text, /100,00 €/);
});

test('art. 11 : apres la grace et une mise en demeure ; facture laissee due sans nouvelle tentative ; aucun remboursement', async () => {
  const {contractId, subscriptionId, sub} = await activeContract();
  renewalInThePast(sub, 20);
  const invoiceId = stripe.renew(subscriptionId, {status: 'open'});
  const mirrorRef = db.doc('enseigne_subscriptions/e1');
  await mirrorRef.set({grace_until: Timestamp.fromMillis(Date.now() + kDay)}, {merge: true});
  await h.rejectsWith(endContract(contractId, {reason: 'unpaid_termination'}), 'notice_required');
  const notice = {noticeSentAt: new Date(Date.now() - 2 * kDay).toISOString(), noticeReference: 'LRAR 1A 234 567 8901 2'};
  await h.rejectsWith(endContract(contractId, {reason: 'unpaid_termination', ...notice}), 'grace_running');
  await mirrorRef.set({grace_until: Timestamp.fromMillis(Date.now() - 5 * kDay)}, {merge: true});
  const result = await endContract(contractId, {reason: 'unpaid_termination', ...notice});
  assert.equal(result.invoiceOutcome, 'open_no_retry');
  assert.deepEqual(stripe.calls.invoicesUpdate.map((c) => [c.invoiceId, c.params]), [[invoiceId, {auto_advance: false}]]);
  assert.deepEqual(stripe.calls.invoicesVoid, [], 'la somme reste due');
  assert.equal(moneyCalls(), 0);
  assert.equal(stripe.calls.subscriptionsCancel.length, 1);
  const c = await contract(contractId);
  assert.equal(c.end_reason, 'unpaid_termination');
  assert.equal((await internal(contractId)).end.notice_reference, 'LRAR 1A 234 567 8901 2');
  assert.match(sent[0].text, /restant dues demeurent exigibles/);
});

test('art. 11 : aucun impaye en cours -> refus', async () => {
  const {contractId} = await activeContract();
  await h.rejectsWith(endContract(contractId, {reason: 'unpaid_termination', noticeSentAt: new Date(Date.now() - kDay).toISOString(),
    noticeReference: 'x'}), 'not_unpaid');
  // Date de mise en demeure dans le futur : refusee.
  await h.rejectsWith(endContract(contractId, {reason: 'unpaid_termination', noticeSentAt: new Date(Date.now() + 3 * kDay).toISOString(),
    noticeReference: 'x'}), 'invalid_field');
  assert.equal(stripe.calls.subscriptionsCancel.length, 0);
});

test('art. 18 : notification requise sauf mesure immediate ; aucun remboursement', async () => {
  const {contractId} = await activeContract();
  await h.rejectsWith(endContract(contractId, {reason: 'breach'}), 'notice_required');
  assert.equal(stripe.calls.subscriptionsCancel.length, 0);
  const result = await endContract(contractId, {reason: 'breach', immediate: true, detail: 'Lots non remis, risque grave pour les joueurs'});
  assert.equal(result.refundedCents, 0);
  assert.equal(moneyCalls(), 0);
  assert.equal((await contract(contractId)).end_reason, 'breach');
  assert.equal((await internal(contractId)).end.immediate, true);
});

test('art. 23 : plus de 60 jours d\'empechement ; remboursement au prorata calcule par le serveur', async () => {
  const {contractId, sub} = await activeContract();
  await h.rejectsWith(endContract(contractId, {reason: 'force_majeure', impedimentStartedAt: new Date(Date.now() - 30 * kDay).toISOString()}),
    'force_majeure_under_60_days');
  // Periode commencee il y a 100 jours.
  const nowSec = Math.floor(Date.now() / 1000);
  sub.current_period_start = nowSec - 100 * 86400;
  sub.current_period_end = sub.current_period_start + 365 * 86400;
  const initial = Object.values(stripe.store.invoices).find((i) => i.billing_reason === 'subscription_create');
  initial.lines.data[0].period = {start: sub.current_period_start, end: sub.current_period_end};
  const result = await endContract(contractId, {reason: 'force_majeure', impedimentStartedAt: new Date(Date.now() - 70 * kDay).toISOString()});
  const expected = Math.floor(43800 * 265 / 365);
  assert.ok(Math.abs(result.refundedCents - expected) <= 2, `${result.refundedCents} ~ ${expected}`);
  assert.equal(stripe.calls.refundsCreate[0].params.amount, result.refundedCents);
  assert.equal((await contract(contractId)).end_reason, 'force_majeure');
  assert.match(sent[0].text, /au prorata de la période non exécutée \(art\. 23\)/);
});

test('fins admin : reservees a l\'admin, utilisables interrupteur coupe ; pieces validees sans appel Stripe', async () => {
  const {contractId} = await activeContract();
  await h.rejectsWith(end.adminEndContractHandler({contractId, reason: 'breach', immediate: true, detail: 'x'}, h.merchantContext()),
    'permission-denied');
  await h.rejectsWith(endContract(contractId, {reason: 'autre'}), 'invalid_field');
  await h.rejectsWith(endContract(contractId, {reason: 'breach', immediate: true, detail: ''}), 'invalid_field');
  assert.equal(stripe.calls.subscriptionsCancel.length, 0);
  await h.setConfig({enabled: false});
  const result = await endContract(contractId, {reason: 'breach', immediate: true});
  assert.equal(result.outcome, 'ended');
});

test('prorata : bornes et arrondi inferieur', () => {
  const start = Date.UTC(2027, 0, 1);
  const endMs = Date.UTC(2028, 0, 1);
  assert.equal(end.prorataCents(43800, start, endMs, start), 43800);
  assert.equal(end.prorataCents(43800, start, endMs, endMs), 0);
  assert.equal(end.prorataCents(43800, start, endMs, start + (endMs - start) / 2), 21900);
  assert.equal(end.prorataCents(43801, start, endMs, start + (endMs - start) / 2), 21900);
  assert.equal(end.prorataCents(43800, start, endMs, start - kDay), 43800);
});
