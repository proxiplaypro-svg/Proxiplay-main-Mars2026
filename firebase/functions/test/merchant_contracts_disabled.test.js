// Phase 1 : interrupteur app_config/merchant_contracts.enabled.
// Correctif t2b : l'interrupteur met en PAUSE LES NOUVELLES VENTES seulement.
//
// Different de true (absent, false, "true", 1...) :
//   - apercu et envoi d'une nouvelle demande : aucun effet (refus avant toute
//     ecriture, aucun e-mail) ;
//   - les contrats existants restent suivis : espace commercant, signalement
//     de visite, retractation, page de paiement et session Checkout d'un
//     contrat deja invite, desactivation du renouvellement, webhook ;
//   - les fonctions ADMIN restent utilisables (commerciaux, liens, codes,
//     verification, refus, confirmation d'une demande deja recue, alertes,
//     configuration).
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const {getMyMerchantContractsHandler} = require('../merchant_contracts_account');
const request = require('../merchant_contracts_request');
const origin = require('../merchant_contract_origin');
const review = require('../merchant_contract_review');
const {runMerchantContractAlerts} = require('../merchant_contract_alerts');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');
const {adminUpdateMerchantContractsConfigHandler} = require('../merchant_contracts_config');
const {makeContractStripe} = require('./stripe_contract_fake.cjs');
const stripeClientModule = require('../stripe_client');
const payment = require('../merchant_contract_payment');
const checkout = require('../merchant_contract_checkout');
const withdrawal = require('../merchant_contract_withdrawal');
const {dispatchEvent} = require('../stripe_webhook');

const {db} = h;

// Nouvelles ventes : sans effet tant que l'interrupteur n'est pas strictement true.
const kBlockedCalls = [
  ['previewMerchantContract (commercant)', () => request.previewMerchantContractHandler({offerId: 'autonome'}, h.merchantContext())],
  ['submitMerchantSubscriptionRequest (commercant)', () => request.submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext())],
];

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

async function seed() {
  await h.clearFirestore();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await db.doc('merchant_contracts/c1').set({
    owner_uid: 'merchant', owner_email: 'merchant@example.test', state: 'submitted', state_version: 1,
    enseigne_id: 'e1', enseigne_name: 'Boutique e1', siret: '98896837600018', offer: {id: 'autonome', label: 'Autonome'},
    origin: {type: 'spontanee'}, cgv: {version: '2.1', sha256: h.kCgvSha256},
    submitted_at: h.admin.firestore.Timestamp.fromMillis(Date.UTC(2026, 0, 5, 9)),
  });
  await db.doc('merchant_contracts/c1/internal/record').set({verification: {checks: allPass}, alerts: {}, emails: {}});
  await db.doc('sales_reps/rep1').set({name: 'Alex Commercial', active: true});
}

const kSwitchStates = [
  ['document absent', null],
  ['enabled: false', {enabled: false}],
  ['enabled: "true" (chaine)', {enabled: 'true'}],
  ['enabled: 1', {enabled: 1}],
];

test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

for (const [label, config] of kSwitchStates) {
  test(`interrupteur ${label} : nouvelles ventes sans aucun effet, contrats existants visibles`, async () => {
    await seed();
    if (config) await db.doc('app_config/merchant_contracts').set({...config, cgv: h.kCgv});
    const sent = h.captureMail(mail);
    cgvDocument.setLoader(async () => h.kCgvBytes);
    const before = await h.snapshotAll();
    for (const [name, call] of kBlockedCalls) {
      const error = await h.rejectsWith(call(), 'contracts_disabled').catch((caught) => {
        throw new Error(`${name} : ${caught.message}`);
      });
      assert.equal(error.details.reason, 'contracts_disabled', name);
    }
    const view = await getMyMerchantContractsHandler({}, h.merchantContext());
    assert.equal(view.salesOpen, false);
    assert.deepEqual(view.contracts.map((c) => c.id), ['c1']);
    assert.deepEqual(view.offers, [], 'aucun catalogue : pas de nouvelle demande');
    assert.deepEqual(await h.snapshotAll(), before, 'aucune ecriture');
    assert.equal(sent.length, 0, 'aucun e-mail');
  });
}

test('interrupteur coupe : les fonctions admin restent utilisables pour preparer l\'ouverture', async () => {
  await seed();
  await db.doc('app_config/merchant_contracts').set({enabled: false, cgv: h.kCgv, admin_alert_email: 'alertes@proxiplay.test'});
  const sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);

  const {repId} = await origin.adminUpsertSalesRepHandler({name: 'Sam Commercial'}, h.adminContext());
  assert.ok((await db.doc(`sales_reps/${repId}`).get()).exists);
  const link = await origin.adminCreateRepLinkHandler({repId}, h.adminContext());
  assert.ok((await db.doc(`rep_links/${origin.hashToken(link.token)}`).get()).exists);
  await request.adminUpsertPromoCodeHandler({code: 'OUVERTURE', kind: 'percent', value: 10, repId}, h.adminContext());
  assert.equal((await db.doc('promo_codes/OUVERTURE').get()).data().rep_id, repId);

  const similar = await review.adminFindSimilarEnseignesHandler({contractId: 'c1'}, h.adminContext());
  assert.deepEqual(similar.enseignes.map((e) => e.id), ['e1']);
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler(
    {contractId: 'c1', expectedVersion: 1, checks: {siret: {result: 'pass', note: 'ok'}}}, h.adminContext());
  assert.equal(stateVersion, 2);

  // Alertes : l'art. 4.1 s'applique aux demandes deja recues.
  const stats = await runMerchantContractAlerts({nowMs: Date.UTC(2026, 1, 1)});
  assert.equal(stats.priority, 1);
  assert.equal(sent.at(-1).to, 'alertes@proxiplay.test');

  // Refus (verification) possible ; e-mail au commercant avec le motif (art. 4.1).
  await review.adminRefuseMerchantContractHandler({contractId: 'c1', expectedVersion: 2, motif: 'unavailable'}, h.adminContext());
  assert.equal((await db.doc('merchant_contracts/c1').get()).data().state, 'refused');

  // Configuration : l'outil fonctionne interrupteur coupe.
  const result = await adminUpdateMerchantContractsConfigHandler({adminAlertEmail: 'nouvelle@proxiplay.test'}, h.adminContext());
  assert.equal(result.enabled, false);
  assert.equal(result.adminAlertEmail, 'nouvelle@proxiplay.test');
});

test('les fonctions admin restent reservees a l\'admin, interrupteur coupe ou non', async () => {
  await seed();
  for (const call of [
    () => origin.adminUpsertSalesRepHandler({name: 'X Y'}, h.merchantContext()),
    () => origin.adminCreateRepLinkHandler({repId: 'rep1'}, h.merchantContext()),
    () => request.adminUpsertPromoCodeHandler({code: 'X10', kind: 'percent', value: 10}, h.merchantContext()),
    () => review.adminRecordMerchantContractChecksHandler({contractId: 'c1', expectedVersion: 1, checks: allPass}, h.merchantContext()),
    () => review.adminRefuseMerchantContractHandler({contractId: 'c1', expectedVersion: 1, motif: 'fraud'}, h.merchantContext()),
    () => review.adminFindSimilarEnseignesHandler({contractId: 'c1'}, h.merchantContext()),
    () => adminUpdateMerchantContractsConfigHandler({enabled: false}, h.merchantContext()),
  ]) {
    await h.rejectsWith(call(), 'permission-denied');
  }
});

// Correctif t2b : un contrat conclu ou en cours n'est jamais bloque par la pause.
test('ventes en pause : confirmation, page de paiement, Checkout, webhook, signalement et retractation fonctionnent', async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  for (const id of ['e1', 'e2', 'e3', 'e4']) await h.seedEnseigne(id, 'merchant');
  const sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
  const stripe = makeContractStripe();
  stripeClientModule.getStripeClient = () => stripe;
  const submit = async (enseigneId, extra = {}) => (await request.submitMerchantSubscriptionRequestHandler({
    enseigneId, siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true, ...extra,
  }, h.merchantContext())).contractId;
  const confirm = async (contractId) => {
    const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
    return adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  };
  const state = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data().state;

  // Avant la pause : une demande spontanee confirmee (invitee), une demarchee
  // confirmee (en retractation), une demande recue non encore confirmee.
  const invited = await submit('e1');
  await confirm(invited);
  const token = /paiement=([A-Za-z0-9_-]+)/.exec([...sent].reverse().find((m) => /invitation à régler/.test(m.subject)).text)[1];
  const pending = await submit('e2', {visitDeclared: true});
  await confirm(pending);
  const received = await submit('e3');
  assert.deepEqual([await state(invited), await state(pending), await state(received)], ['payment_invited', 'withdrawal_pending', 'submitted']);

  await h.setConfig({enabled: false});
  await h.rejectsWith(submit('e4'), 'contracts_disabled');

  // Admin : confirmation d'une demande deja recue.
  await confirm(received);
  assert.equal(await state(received), 'payment_invited');

  // Page de paiement et session Checkout d'un contrat deja invite, puis webhook.
  const view = await payment.getPaymentInvitationHandler({token}, h.merchantContext());
  assert.equal(view.contractId, invited);
  const urls = {successUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=success',
    cancelUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=cancel'};
  const created = await checkout.createContractCheckoutSessionHandler({token, ...urls}, h.merchantContext());
  assert.match(created.checkoutUrl, /^https:\/\/checkout\.stripe\.com\//);
  const sessionId = Object.keys(stripe.store.sessions)[0];
  stripe.complete(sessionId);
  const session = stripe.store.sessions[sessionId];
  await dispatchEvent(db, stripe.event('checkout.session.completed', {id: session.id, object: 'checkout.session', mode: 'subscription',
    subscription: session.subscription, metadata: session.metadata}));
  assert.equal(await state(invited), 'active');
  assert.equal(stripe.calls.refundsCreate.length, 0, 'paiement legitime : jamais rembourse');

  // Signalement d'une visite et retractation.
  assert.equal((await origin.reportMerchantVisitHandler({contractId: invited}, h.merchantContext())).changed, true);
  const result = await withdrawal.withdrawMerchantContractHandler({contractId: pending}, h.merchantContext());
  assert.equal(result.state, 'withdrawn');
});
