// Relecture des regles : le document principal merchant_contracts/{id} est
// lisible par le commercant. Apres la creation et apres chaque transition,
// ses champs doivent appartenir a une liste blanche ; aucun champ interne
// (notes, resultats de verification, motif interne, preuves d'origine,
// adresse IP, journal, alertes, e-mails, confirmation) ne doit y apparaitre.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const request = require('../merchant_contracts_request');
const origin = require('../merchant_contract_origin');
const review = require('../merchant_contract_review');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');

const {db} = h;

// Liste blanche exacte : champ de premier niveau -> sous-champs autorises
// (null = valeur simple).
const kWhitelist = Object.freeze({
  owner_uid: null,
  owner_email: null,
  state: null,
  state_version: null,
  enseigne_id: null,
  enseigne_name: null,
  enseigne_request: ['name', 'address', 'postal_code', 'city'],
  siret: null,
  raison_sociale: null,
  offer: ['id', 'label', 'currency', 'vat_rate_basis_points', 'catalog_ht_cents', 'discount_ht_cents',
    'first_year_ht_cents', 'first_year_ttc_cents', 'renewal_ht_cents', 'renewal_ttc_cents', 'duration_months'],
  promo: ['code', 'discount_ht_cents'],
  cgv: ['version', 'sha256', 'url', 'accepted_at'],
  jurisdiction_clause_accepted_at: null,
  origin: ['type', 'decided_at', 'reported_at'],
  submitted_at: null,
  updated_at: null,
  refused_at: null,
  public_refusal: ['motif', 'detail'],
  confirmed_at: null,
  visit_report_deadline: null,
  // Tranche 2a
  withdrawal_deadline: null,
  withdrawn_at: null,
  payment_invited_at: null,
  payment_link_expires_at: null,
  activated_at: null,
  ended_at: null,
  end_reason: null,
  // Tranche 2b, lot 1.9
  closed_at: null,
});

// Termes qui ne doivent jamais apparaitre, ni comme cle ni comme valeur.
const kForbiddenKeys = ['verification', 'checks', 'note', 'notes', 'internalNote', 'refusal_reason', 'refused_by',
  'reviewer_uid', 'origin_evidence', 'sources', 'rep_id', 'link_hash', 'evidence', 'ip', 'acceptance', 'events',
  'alerts', 'emails', 'confirmation', 'lock_at', 'lock_by', 'confirmed_by', 'user_agent',
  // Tranche 2a : jamais dans la vue commercant.
  'token', 'token_hash', 'payment_invitation', 'withdrawal', 'refund', 'late_payment', 'stripe_customer_id',
  'stripe_subscription_id', 'last_session_id',
  // Tranche 2b : rappels et relances restent internes.
  'reminder_sent_at', 'reminder_queued_at', 'grace_reminders', 'renewal_failures', 'missed'];

function assertWhitelisted(label, data, {forbiddenValues = []} = {}) {
  for (const [key, value] of Object.entries(data)) {
    assert.ok(Object.prototype.hasOwnProperty.call(kWhitelist, key), `${label} : champ non autorise « ${key} »`);
    const allowed = kWhitelist[key];
    if (allowed && value !== null && typeof value === 'object' && !(value instanceof h.admin.firestore.Timestamp)) {
      for (const sub of Object.keys(value)) {
        assert.ok(allowed.includes(sub), `${label} : sous-champ non autorise « ${key}.${sub} »`);
      }
    }
  }
  const walk = (value, path) => {
    if (value && typeof value === 'object' && !(value instanceof h.admin.firestore.Timestamp)) {
      for (const [key, sub] of Object.entries(value)) {
        assert.ok(!kForbiddenKeys.includes(key), `${label} : cle interne « ${path}${key} »`);
        walk(sub, `${path}${key}.`);
      }
    }
  };
  walk(data, '');
  const text = JSON.stringify(data);
  for (const secret of forbiddenValues) {
    assert.ok(!text.includes(secret), `${label} : valeur interne presente (${secret})`);
  }
}

const read = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();
const kIp = '203.0.113.77';
const kNote = 'NOTE-INTERNE-CONFIDENTIELLE';
const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass', note: kNote}]));

function submit(overrides = {}) {
  return request.submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
    userAgent: 'Mozilla/5.0 test', ...overrides,
  }, h.merchantContext('merchant', kIp));
}

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'merchant');
  h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

test('creation (lien de commercial, code, case visite) puis signalement : liste blanche respectee', async () => {
  const {repId} = await origin.adminUpsertSalesRepHandler({name: 'Alex Commercial'}, h.adminContext());
  const link = await origin.adminCreateRepLinkHandler({repId}, h.adminContext());
  await request.adminUpsertPromoCodeHandler({code: 'ALEX10', kind: 'percent', value: 10, repId}, h.adminContext());
  const values = [kIp, repId, origin.hashToken(link.token), link.token, 'Mozilla/5.0 test'];

  const withLink = await submit({repLinkToken: link.token, promoCode: 'ALEX10', visitDeclared: true});
  assertWhitelisted('creation demarchee', await read(withLink.contractId), {forbiddenValues: values});

  const fresh = await submit({enseigneId: undefined, siret: '98896837600026',
    enseigneRequest: {name: 'La Boulangerie', address: '3 place Jean Bart', postalCode: '59140', city: 'Dunkerque'}});
  assertWhitelisted('creation nouvelle enseigne', await read(fresh.contractId), {forbiddenValues: values});

  const spontaneous = await submit({enseigneId: 'e2'});
  assertWhitelisted('creation spontanee', await read(spontaneous.contractId), {forbiddenValues: values});
  await origin.reportMerchantVisitHandler({contractId: spontaneous.contractId}, h.merchantContext());
  assertWhitelisted('signalement de visite', await read(spontaneous.contractId), {forbiddenValues: values});
});

test('controles, rattachement d\'enseigne, refus motive : liste blanche respectee', async () => {
  const {contractId} = await submit({enseigneId: undefined,
    enseigneRequest: {name: 'La Boulangerie', address: '3 place Jean Bart', postalCode: '59140', city: 'Dunkerque'}});
  await h.seedEnseigne('nouvelle', 'merchant');
  await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass, enseigneId: 'nouvelle'}, h.adminContext());
  assertWhitelisted('controles et rattachement', await read(contractId), {forbiddenValues: [kIp, kNote]});
  await review.adminRefuseMerchantContractHandler({contractId, expectedVersion: 2, motif: 'activity',
    detail: 'Precision communiquee', internalNote: kNote}, h.adminContext());
  const refused = await read(contractId);
  assertWhitelisted('refus', refused, {forbiddenValues: [kIp, kNote]});
  assert.deepEqual(refused.public_refusal, {motif: 'activity', detail: 'Precision communiquee'});
});

test('confirmation (spontanee et demarchee), y compris apres un echec d\'envoi : liste blanche respectee', async () => {
  for (const [enseigneId, extra] of [['e1', {}], ['e2', {visitDeclared: true}]]) {
    const {contractId} = await submit({enseigneId, ...extra});
    const {stateVersion} = await review.adminRecordMerchantContractChecksHandler(
      {contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
    h.captureMail(mail, {fail: true});
    await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext()), 'confirmation_failed');
    assertWhitelisted('apres echec de confirmation', await read(contractId), {forbiddenValues: [kIp, kNote]});
    h.captureMail(mail);
    const current = (await read(contractId)).state_version;
    await adminConfirmMerchantContractHandler({contractId, expectedVersion: current}, h.adminContext());
    const confirmed = await read(contractId);
    assert.ok(['payment_invited', 'withdrawal_pending'].includes(confirmed.state));
    assertWhitelisted(`confirmation (${enseigneId})`, confirmed, {forbiddenValues: [kIp, kNote, `<contrat-${contractId}@proxiplay.fr>`]});
  }
});

test('lot 1.9 : rappel a J+10 puis cloture a 15 jours : liste blanche respectee', async () => {
  const {runMerchantContractSchedule} = require('../merchant_contract_schedule');
  const {contractId} = await submit({enseigneId: 'e1'});
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  const invitedMs = (await read(contractId)).payment_invited_at.toMillis();
  await runMerchantContractSchedule({db, nowMs: invitedMs + 11 * 86400000});
  assertWhitelisted('apres rappel', await read(contractId), {forbiddenValues: [kIp, kNote]});
  await runMerchantContractSchedule({db, nowMs: invitedMs + 17 * 86400000});
  const closed = await read(contractId);
  assert.equal(closed.state, 'closed_unpaid');
  assertWhitelisted('apres cloture', closed, {forbiddenValues: [kIp, kNote]});
});

test('le controle lui-meme detecte un champ interne (garde-fou du test)', () => {
  assert.throws(() => assertWhitelisted('piege', {state: 'submitted', verification: {}}), /champ non autorise/);
  assert.throws(() => assertWhitelisted('piege', {origin: {type: 'demarchee', rep_id: 'r'}}), /sous-champ non autorise/);
  assert.throws(() => assertWhitelisted('piege', {owner_email: kIp}, {forbiddenValues: [kIp]}), /valeur interne/);
});
