// Phase 1, tranche 1 : avec app_config/merchant_contracts.enabled different
// de true (absent, false, "true"...), AUCUNE fonction de la tranche n'a
// d'effet : refus (ou reponse vide) avant toute ecriture, aucun e-mail.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const {getMyMerchantContractsHandler} = require('../merchant_contracts_account');
const request = require('../merchant_contracts_request');
const origin = require('../merchant_contract_origin');
const review = require('../merchant_contract_review');

const {db} = h;

// Chaque entree : [nom, appel]. Les lots suivants completent cette liste.
const kCalls = [
  ['previewMerchantContract', () => request.previewMerchantContractHandler({offerId: 'autonome'}, h.merchantContext())],
  ['submitMerchantSubscriptionRequest', () => request.submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext())],
  ['adminUpsertPromoCode', () => request.adminUpsertPromoCodeHandler({code: 'X10', kind: 'percent', value: 10}, h.adminContext())],
  // lot 1.4b
  ['reportMerchantVisit', () => origin.reportMerchantVisitHandler({contractId: 'c1'}, h.merchantContext())],
  ['adminUpsertSalesRep', () => origin.adminUpsertSalesRepHandler({name: 'Alex Commercial'}, h.adminContext())],
  ['adminCreateRepLink', () => origin.adminCreateRepLinkHandler({repId: 'rep1'}, h.adminContext())],
  // lot 1.2-min
  ['adminRecordMerchantContractChecks', () => review.adminRecordMerchantContractChecksHandler(
    {contractId: 'c1', expectedVersion: 1, checks: {siret: {result: 'pass'}}}, h.adminContext())],
  ['adminRefuseMerchantContract', () => review.adminRefuseMerchantContractHandler(
    {contractId: 'c1', expectedVersion: 1, motif: 'fraud'}, h.adminContext())],
  ['adminFindSimilarEnseignes', () => review.adminFindSimilarEnseignesHandler({contractId: 'c1'}, h.adminContext())],
  // lot 1.3 (tache planifiee) : demande c1 recue il y a longtemps, alerte due.
  ['merchantContractAlerts', () => require('../merchant_contract_alerts').runMerchantContractAlerts({nowMs: Date.UTC(2026, 1, 1)})],
];

async function seed() {
  await h.clearFirestore();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await db.doc('merchant_contracts/c1').set({
    owner_uid: 'merchant', owner_email: 'merchant@example.test', state: 'submitted', state_version: 1,
    enseigne_id: 'e1', siret: '98896837600018', offer: {id: 'autonome'}, origin: {type: 'spontanee'},
    cgv: {version: '2.1', sha256: h.kCgvSha256}, submitted_at: h.admin.firestore.Timestamp.fromMillis(Date.UTC(2026, 0, 5, 9)),
  });
  await db.doc('merchant_contracts/c1/internal/record').set({verification: {checks: {}}, alerts: {}, emails: {}});
  await db.doc('sales_reps/rep1').set({name: 'Alex Commercial', active: true});
}

for (const [label, config] of [
  ['document absent', null],
  ['enabled: false', {enabled: false}],
  ['enabled: "true" (chaine)', {enabled: 'true'}],
  ['enabled: 1', {enabled: 1}],
]) {
  test(`interrupteur ${label} : aucune fonction de la tranche n'a d'effet`, async () => {
    await seed();
    if (config) await db.doc('app_config/merchant_contracts').set({...config, cgv: h.kCgv});
    const sent = h.captureMail(mail);
    const before = await h.snapshotAll();
    for (const [name, call] of kCalls) {
      let result;
      let error = null;
      try {
        result = await call();
      } catch (caught) {
        error = caught;
      }
      if (error) {
        assert.equal(error.details?.reason, 'contracts_disabled', `${name} : ${error.message}`);
      } else {
        assert.ok(result?.enabled === false || result?.skipped === 'contracts_disabled', `${name} : ${JSON.stringify(result)}`);
      }
    }
    assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext()), {enabled: false});
    assert.deepEqual(await h.snapshotAll(), before, 'aucune ecriture');
    assert.equal(sent.length, 0, 'aucun e-mail');
    mail.setSender(null);
  });
}

module.exports = {kCalls};
