// Phase 1, tranche 1, lot 1.2-min : verification manuelle et refus motive.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const {submitMerchantSubscriptionRequestHandler} = require('../merchant_contracts_request');
const {getMyMerchantContractsHandler} = require('../merchant_contracts_account');
const review = require('../merchant_contract_review');

const {db} = h;
let sent;

async function submit(overrides = {}) {
  return submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
    ...overrides,
  }, h.merchantContext());
}

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass', note: `${name} ok`}]));

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

test('saisie des 8 controles : auteur, date, version incrementee, journal ; notes jamais visibles du commercant', async () => {
  const {contractId} = await submit();
  const result = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  assert.equal(result.stateVersion, 2);
  const internal = (await db.doc(`merchant_contracts/${contractId}/internal/record`).get()).data();
  assert.equal(Object.keys(internal.verification.checks).length, 8);
  assert.equal(internal.verification.checks.fraud.by, 'admin');
  assert.ok(internal.verification.checks.fraud.at);
  assert.equal(internal.verification.reviewer_uid, 'admin');
  const events = await db.collection(`merchant_contracts/${contractId}/events`).where('type', '==', 'checks_recorded').get();
  assert.equal(events.size, 1);
  const view = await getMyMerchantContractsHandler({}, h.merchantContext());
  assert.ok(!JSON.stringify(view).includes('fraud ok'));
});

test('version perimee, controle inconnu ou resultat invalide : refuse', async () => {
  const {contractId} = await submit();
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 7, checks: allPass}, h.adminContext()), 'stale_version');
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: {humeur: {result: 'pass'}}}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: {siret: {result: 'ok'}}}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.merchantContext()), 'permission-denied');
});

test('nouvelle enseigne : l\'admin la cree au nom du demandeur puis la rattache ; enseigne d\'un tiers ou occupee refusee', async () => {
  const {contractId} = await submit({enseigneId: undefined,
    enseigneRequest: {name: 'La Boulangerie', address: '3 place Jean Bart', postalCode: '59140', city: 'Dunkerque'}});
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, enseigneId: 'e2'}, h.adminContext()), 'enseigne_not_owned');
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, enseigneId: 'absente'}, h.adminContext()), 'enseigne_not_owned');
  await h.seedEnseigne('nouvelle', 'merchant', {name: 'La Boulangerie'});
  await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, enseigneId: 'nouvelle'}, h.adminContext());
  const contract = (await db.doc(`merchant_contracts/${contractId}`).get()).data();
  assert.equal(contract.enseigne_id, 'nouvelle');
  assert.equal(contract.enseigne_name, 'La Boulangerie');
  // Une seconde demande ne peut pas rattacher la meme enseigne.
  const second = await submit({enseigneId: undefined, siret: '98896837600026',
    enseigneRequest: {name: 'La Boulangerie bis', address: '4 place Jean Bart', postalCode: '59140', city: 'Dunkerque'}});
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId: second.contractId, expectedVersion: 1, enseigneId: 'nouvelle'}, h.adminContext()), 'enseigne_busy');
});

test('refus motive (art. 4.1) : etat refused, motif communique, note interne cachee, e-mail ; plus de decision ensuite', async () => {
  const {contractId} = await submit();
  sent.length = 0;
  const result = await review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 1, motif: 'activity',
    detail: 'Activité exclue par la politique commerciale', internalNote: 'vu sur Annuaire : activite de jeux d\'argent'}, h.adminContext());
  assert.deepEqual(result, {state: 'refused', notified: true});
  const contract = (await db.doc(`merchant_contracts/${contractId}`).get()).data();
  assert.equal(contract.state, 'refused');
  assert.deepEqual(contract.public_refusal, {motif: 'activity', detail: 'Activité exclue par la politique commerciale'});
  assert.ok(!JSON.stringify(contract).includes('Annuaire'));
  const internal = (await db.doc(`merchant_contracts/${contractId}/internal/record`).get()).data();
  assert.match(internal.refusal_reason, /Annuaire/);
  assert.ok(internal.emails.refusal.sent_at);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'merchant@example.test');
  assert.match(sent[0].text, /Motif \(CGV, art\. 4\.1\) : Activité incompatible avec les règles de PROXIPLAY — Activité exclue/);
  assert.doesNotMatch(sent[0].text, /Annuaire/);
  assert.match(sent[0].text, /Aucun contrat n'a été conclu et aucune somme n'a été encaissée/);
  await h.rejectsWith(review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 2, motif: 'fraud'}, h.adminContext()), 'not_submitted');
  await h.rejectsWith(review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 2, checks: allPass}, h.adminContext()), 'not_submitted');
});

test('refus apres confirmation impossible ; motif hors art. 4.1 refuse', async () => {
  await db.doc('merchant_contracts/conf').set({owner_uid: 'merchant', state: 'confirmed', state_version: 4});
  await h.rejectsWith(review.adminRefuseMerchantContractHandler({contractId: 'conf', expectedVersion: 4, motif: 'fraud'}, h.adminContext()), 'not_submitted');
  const {contractId} = await submit();
  await h.rejectsWith(review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 1, motif: 'humeur'}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 1, motif: 'fraud'}, h.merchantContext()), 'permission-denied');
});

test('deux refus concurrents sur la meme version : un seul passe', async () => {
  const {contractId} = await submit();
  const results = await Promise.allSettled([
    review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 1, motif: 'fraud'}, h.adminContext()),
    review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 1, motif: 'activity'}, h.adminContext()),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const events = await db.collection(`merchant_contracts/${contractId}/events`).where('type', '==', 'refused').get();
  assert.equal(events.size, 1);
});

test('doublon : enseignes de meme nom normalise et code postal, meme fiche Google, enseignes du demandeur, meme SIRET', async () => {
  await h.seedEnseigne('homonyme', 'other', {name: 'BOUTIQUE  é1', area_code: '59240'});
  await h.seedEnseigne('autre-ville', 'other', {name: 'Boutique e1', area_code: '75001'});
  await h.seedEnseigne('meme-fiche', 'other', {name: 'Autre nom', area_code: '62100', google_place_id: 'place-1'});
  await db.doc('enseignes/e1').update({google_place_id: 'place-1'});
  const {contractId} = await submit();
  await db.doc('merchant_contracts/ancien').set({owner_uid: 'other', state: 'refused', siret: '98896837600018', enseigne_name: 'X'});
  const result = await review.adminFindSimilarEnseignesHandler({contractId}, h.adminContext());
  const ids = result.enseignes.map((e) => e.id).sort();
  // e1 : enseigne du demandeur ; homonyme : meme nom normalise et meme code
  // postal ; meme-fiche : meme fiche Google. autre-ville : non.
  assert.deepEqual(ids, ['e1', 'homonyme', 'meme-fiche']);
  assert.equal(review.normalizeName('BOUTIQUE  é1'), 'boutique e1');
  assert.deepEqual(result.contractsWithSameSiret.map((c) => c.id), ['ancien']);
  await h.rejectsWith(review.adminFindSimilarEnseignesHandler({contractId}, h.merchantContext()), 'permission-denied');
});
