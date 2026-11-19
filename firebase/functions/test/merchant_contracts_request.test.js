// Phase 1, tranche 1, lot 1.1 : demande de souscription.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const {
  previewMerchantContractHandler,
  submitMerchantSubscriptionRequestHandler,
  adminUpsertPromoCodeHandler,
  clientIp,
} = require('../merchant_contracts_request');

const {db, admin} = h;
let sent;

function request(overrides = {}) {
  return {
    enseigneId: 'e1',
    siret: '988 968 376 00018',
    raisonSociale: 'PROXIPLAY TEST SAS',
    offerId: 'autonome',
    cgvAccepted: true,
    cgvVersion: h.kCgv.version,
    cgvSha256: h.kCgvSha256,
    jurisdictionClauseAccepted: true,
    ...overrides,
  };
}

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'other');
  sent = h.captureMail(mail);
});
test.after(() => mail.setSender(null));

test('demande valide : etat submitted, prix du catalogue, preuve d\'acceptation, e-mails accuse et admin', async () => {
  const result = await submitMerchantSubscriptionRequestHandler(request({offerId: 'accompagnee', amountHtCents: 1}), h.merchantContext());
  assert.equal(result.state, 'submitted');
  assert.equal(result.origin, 'spontanee');
  const contract = (await db.doc(`merchant_contracts/${result.contractId}`).get()).data();
  assert.equal(contract.owner_uid, 'merchant');
  assert.equal(contract.state_version, 1);
  assert.equal(contract.enseigne_id, 'e1');
  assert.equal(contract.siret, '98896837600018');
  assert.equal(contract.offer.first_year_ht_cents, 100000, 'jamais un montant fourni par le client');
  assert.equal(contract.offer.first_year_ttc_cents, 120000);
  assert.equal(contract.cgv.version, '2.1');
  assert.equal(contract.cgv.sha256, h.kCgvSha256);
  assert.ok(contract.cgv.accepted_at.toMillis() > 0, 'heure serveur');
  assert.ok(contract.jurisdiction_clause_accepted_at.toMillis() > 0);
  assert.ok(!('user_agent' in contract) && !JSON.stringify(contract).includes('203.0.113.7'), 'ni navigateur ni IP dans la vue commercant');
  const internal = (await db.doc(`merchant_contracts/${result.contractId}/internal/record`).get()).data();
  assert.equal(internal.acceptance.ip, '203.0.113.7');
  assert.equal(internal.acceptance.cgv_sha256, h.kCgvSha256);
  assert.ok(!('user_agent' in internal.acceptance));
  assert.ok(internal.emails.request_ack.sent_at);
  assert.ok(internal.emails.admin_new_request.sent_at);
  const events = await db.collection(`merchant_contracts/${result.contractId}/events`).get();
  assert.deepEqual(events.docs.map((d) => d.data().type), ['submitted']);
  assert.deepEqual(sent.map((m) => m.to), ['merchant@example.test', 'alertes@proxiplay.test']);
  assert.match(sent[0].text, /n'est pas une confirmation/);
  assert.match(sent[0].text, /Aucune somme n'est encaissée/);
  assert.match(sent[0].text, /1 200,00 € TTC/);
});

test('nouvelle enseigne decrite : enseigne_id vide, l\'admin la creera avant la confirmation', async () => {
  const result = await submitMerchantSubscriptionRequestHandler(request({
    enseigneId: undefined,
    enseigneRequest: {name: 'La Boulangerie', address: '3 place Jean Bart', postalCode: '59140', city: 'Dunkerque'},
  }), h.merchantContext());
  const contract = (await db.doc(`merchant_contracts/${result.contractId}`).get()).data();
  assert.equal(contract.enseigne_id, null);
  assert.deepEqual(contract.enseigne_request, {name: 'La Boulangerie', address: '3 place Jean Bart', postal_code: '59140', city: 'Dunkerque'});
});

test('le SIRET peut etre partage : deux enseignes du meme SIRET, deux demandes', async () => {
  await h.seedEnseigne('e3', 'merchant');
  await submitMerchantSubscriptionRequestHandler(request(), h.merchantContext());
  await submitMerchantSubscriptionRequestHandler(request({enseigneId: 'e3'}), h.merchantContext());
  const all = await db.collection('merchant_contracts').where('siret', '==', '98896837600018').get();
  assert.equal(all.size, 2);
});

test('une seule demande ouverte par enseigne', async () => {
  await submitMerchantSubscriptionRequestHandler(request(), h.merchantContext());
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request(), h.merchantContext()), 'enseigne_busy');
});

test('refus : CGV non acceptees, version ou empreinte depassee, clause art. 25, SIRET, enseigne d\'un tiers, champs', async () => {
  const ctx = h.merchantContext();
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({cgvAccepted: 'true'}), ctx), 'cgv_not_accepted');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({cgvVersion: '2.0'}), ctx), 'cgv_outdated');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({cgvSha256: 'a'.repeat(64)}), ctx), 'cgv_outdated');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({jurisdictionClauseAccepted: false}), ctx), 'jurisdiction_not_accepted');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({siret: '98896837600019'}), ctx), 'invalid_siret');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({enseigneId: 'e2'}), ctx), 'enseigne_not_owned');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({enseigneId: 'absente'}), ctx), 'enseigne_not_owned');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({offerId: 'custom'}), ctx), 'invalid-argument');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({raisonSociale: ' '}), ctx), 'invalid_field');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({enseigneId: undefined, enseigneRequest: {name: 'X'}}), ctx), 'invalid_field');
  assert.equal((await db.collection('merchant_contracts').get()).size, 0);
  assert.equal(sent.length, 0);
});

test('CGV non configurees (PDF date absent) : aucune demande acceptee', async () => {
  await h.setConfig({cgv: null});
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request(), h.merchantContext()), 'cgv_not_configured');
  await h.rejectsWith(previewMerchantContractHandler({offerId: 'autonome'}, h.merchantContext()), 'cgv_not_configured');
});

test('au plus 3 demandes en attente par compte', async () => {
  for (const id of ['e3', 'e4', 'e5', 'e6']) await h.seedEnseigne(id, 'merchant');
  for (const id of ['e3', 'e4', 'e5']) await submitMerchantSubscriptionRequestHandler(request({enseigneId: id}), h.merchantContext());
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request({enseigneId: 'e6'}), h.merchantContext()), 'too_many_pending');
});

test('reserve aux comptes commercants ; un joueur ne peut rien demander', async () => {
  await db.doc('users/player').set({user_role: 'joueur'});
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request(), h.merchantContext('player')), 'permission-denied');
  await h.rejectsWith(submitMerchantSubscriptionRequestHandler(request(), {}), 'unauthenticated');
});

test('echec SMTP : la demande reste enregistree, l\'echec est trace en interne', async () => {
  h.captureMail(mail, {fail: true});
  const result = await submitMerchantSubscriptionRequestHandler(request(), h.merchantContext());
  const internal = (await db.doc(`merchant_contracts/${result.contractId}/internal/record`).get()).data();
  assert.match(internal.emails.request_ack.error, /smtp indisponible/);
  assert.equal((await db.doc(`merchant_contracts/${result.contractId}`).get()).data().state, 'submitted');
});

test('code promotionnel du miroir : remise premiere annee, renouvellement plein tarif ; code invalide refuse', async () => {
  await adminUpsertPromoCodeHandler({code: 'bienvenue', kind: 'amount', value: 6500, offers: ['autonome']}, h.adminContext());
  const preview = await previewMerchantContractHandler({offerId: 'autonome', promoCode: 'BIENVENUE'}, h.merchantContext());
  assert.equal(preview.offer.first_year_ht_cents, 30000);
  assert.equal(preview.offer.first_year_ttc_cents, 36000);
  assert.equal(preview.offer.renewal_ttc_cents, 43800);
  assert.equal(preview.origin, 'spontanee');
  const result = await submitMerchantSubscriptionRequestHandler(request({promoCode: 'bienvenue'}), h.merchantContext());
  const contract = (await db.doc(`merchant_contracts/${result.contractId}`).get()).data();
  assert.deepEqual(contract.promo, {code: 'BIENVENUE', discount_ht_cents: 6500});
  await h.rejectsWith(previewMerchantContractHandler({offerId: 'accompagnee', promoCode: 'BIENVENUE'}, h.merchantContext()), 'promo_invalid');
  await h.rejectsWith(previewMerchantContractHandler({offerId: 'autonome', promoCode: 'INCONNU'}, h.merchantContext()), 'promo_invalid');
  await adminUpsertPromoCodeHandler({code: 'BIENVENUE', kind: 'amount', value: 6500, active: false}, h.adminContext());
  await h.rejectsWith(previewMerchantContractHandler({offerId: 'autonome', promoCode: 'BIENVENUE'}, h.merchantContext()), 'promo_invalid');
  await adminUpsertPromoCodeHandler({code: 'PASSE', kind: 'percent', value: 10, validUntil: '2020-01-01T00:00:00Z'}, h.adminContext());
  await h.rejectsWith(previewMerchantContractHandler({offerId: 'autonome', promoCode: 'PASSE'}, h.merchantContext()), 'promo_invalid');
});

test('miroir promo_codes : admin seul, aucun identifiant Stripe saisi, remise bornee', async () => {
  await h.rejectsWith(adminUpsertPromoCodeHandler({code: 'X10', kind: 'percent', value: 10}, h.merchantContext()), 'permission-denied');
  await h.rejectsWith(adminUpsertPromoCodeHandler({code: 'X10', kind: 'percent', value: 101}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(adminUpsertPromoCodeHandler({code: 'X10', kind: 'amount', value: 50}, h.adminContext()), 'invalid_field');
  await adminUpsertPromoCodeHandler({code: 'X10', kind: 'percent', value: 10, stripe_promotion_code_id: 'promo_123'}, h.adminContext());
  const doc = (await db.doc('promo_codes/X10').get()).data();
  assert.equal(doc.stripe_promotion_code_id, null);
  assert.equal(doc.first_year_only, true);
  assert.equal(doc.uses, 0);
});

test('adresse IP : premier element de x-forwarded-for, sinon ip de la requete', () => {
  assert.equal(clientIp({rawRequest: {headers: {'x-forwarded-for': '198.51.100.4, 10.0.0.1'}, ip: '10.0.0.1'}}), '198.51.100.4');
  assert.equal(clientIp({rawRequest: {headers: {}, ip: '203.0.113.7'}}), '203.0.113.7');
  assert.equal(clientIp({}), null);
});

test('l\'heure d\'acceptation est celle du serveur, pas une date fournie par le client', async () => {
  const result = await submitMerchantSubscriptionRequestHandler(request({acceptedAt: '2000-01-01'}), h.merchantContext());
  const contract = (await db.doc(`merchant_contracts/${result.contractId}`).get()).data();
  assert.ok(contract.cgv.accepted_at.toMillis() > Date.UTC(2026, 0, 1));
  assert.ok(contract.cgv.accepted_at instanceof admin.firestore.Timestamp);
});
