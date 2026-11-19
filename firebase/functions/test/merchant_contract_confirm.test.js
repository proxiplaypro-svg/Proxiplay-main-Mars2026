// Phase 1, tranche 1, lot 1.4 : confirmation de souscription (art. 4.1, 4.3).
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const paris = require('../paris_time');
const {submitMerchantSubscriptionRequestHandler, adminUpsertPromoCodeHandler} = require('../merchant_contracts_request');
const {getMyMerchantContractsHandler} = require('../merchant_contracts_account');
const review = require('../merchant_contract_review');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');

const {db, admin} = h;
let sent;

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

async function readyContract(overrides = {}, {checks = allPass} = {}) {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
    ...overrides,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks}, h.adminContext());
  sent.length = 0;
  return {contractId, version: stateVersion};
}

const contract = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();
const internal = async (id) => (await db.doc(`merchant_contracts/${id}/internal/record`).get()).data();

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

test('confirmation : contrat conclu a l\'envoi, e-mail durable avec CGV jointes, date limite de signalement, journal', async () => {
  const {contractId, version} = await readyContract();
  const before = Date.now();
  const result = await adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext());
  // Tranche 2a : spontanee -> payment_invited, invitation envoyee avec la confirmation (art. 8.1).
  assert.equal(result.state, 'payment_invited');
  assert.equal(result.invitation, 'sent');
  assert.ok(result.confirmedAt >= before);
  const c = await contract(contractId);
  assert.equal(c.state, 'payment_invited');
  assert.equal(c.withdrawal_deadline.toMillis(), paris.visitReportDeadline(result.confirmedAt));
  assert.equal(c.confirmed_at.toMillis(), result.confirmedAt);
  assert.equal(c.visit_report_deadline.toMillis(), paris.visitReportDeadline(result.confirmedAt));
  const i = await internal(contractId);
  assert.equal(i.confirmation.cgv_sha256, h.kCgvSha256);
  assert.equal(i.confirmation.confirmed_by, 'admin');
  assert.equal(i.confirmation.email_sent_at.toMillis(), result.confirmedAt);
  assert.ok(!('lock_at' in i.confirmation));
  assert.equal(sent.length, 2, 'confirmation puis invitation a payer');
  assert.match(sent[1].subject, /invitation à régler/);
  const message = sent[0];
  assert.equal(message.to, 'merchant@example.test');
  assert.equal(message.messageId, `<contrat-${contractId}@proxiplay.fr>`);
  assert.equal(message.attachments.length, 1);
  assert.equal(message.attachments[0].contentType, 'application/pdf');
  assert.ok(Buffer.compare(message.attachments[0].content, h.kCgvBytes) === 0, 'le PDF joint est celui de l\'empreinte');
  assert.match(message.text, /Le contrat est conclu à la date d'envoi de ce message/);
  assert.match(message.text, new RegExp(`empreinte SHA-256 : ${h.kCgvSha256}`));
  assert.match(message.text, /Prix du renouvellement : 365,00 € HT, soit 438,00 € TTC par an/);
  assert.match(message.text, /aucune somme n'a été encaissée/);
  assert.match(message.text, /Souscription spontanée \(art\. 4\.2\)/);
  assert.match(message.text, /vous pouvez le signaler jusqu'au/);
  assert.doesNotMatch(message.text, /FORMULAIRE DE RÉTRACTATION/);
  const events = await db.collection(`merchant_contracts/${contractId}/events`).where('type', '==', 'confirmed').get();
  assert.equal(events.size, 1);
  const view = await getMyMerchantContractsHandler({}, h.merchantContext());
  assert.equal(view.contracts[0].state, 'payment_invited');
  assert.equal(view.contracts[0].visitReportDeadline, c.visit_report_deadline.toMillis());
});

test('souscription demarchee : informations et formulaire de retractation, aucun paiement pendant 14 jours', async () => {
  const {contractId, version} = await readyContract({visitDeclared: true});
  const {confirmedAt, state, invitation} = await adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext());
  assert.equal(state, 'withdrawal_pending', 'demarchee : aucun paiement demande avant la fin du delai (art. 7.4)');
  assert.equal(invitation, null);
  assert.equal(sent.length, 1, 'confirmation seule, pas d\'invitation a payer');
  const text = sent[0].text;
  assert.match(text, /Droit de rétractation \(souscription démarchée, art\. 7\)/);
  assert.match(text, /quatorze jours à compter du lendemain de la conclusion/);
  const deadline = new Intl.DateTimeFormat('fr-FR', {timeZone: 'Europe/Paris', day: '2-digit', month: '2-digit', year: 'numeric'})
    .format(new Date(paris.visitReportDeadline(confirmedAt)));
  assert.match(text, new RegExp(`jusqu'au ${deadline.replace(/\//g, '\\/')} inclus`));
  assert.match(text, /aucune carte bancaire ni autorisation de prélèvement/);
  assert.match(text, /FORMULAIRE DE RÉTRACTATION/);
  assert.match(text, /contact@proxiplay\.fr/);
  assert.doesNotMatch(text, /Me rétracter/, 'la fonction en ligne arrive en tranche 2');
});

test('code promotionnel : utilisation comptee a la confirmation seulement', async () => {
  await adminUpsertPromoCodeHandler({code: 'BIENVENUE', kind: 'amount', value: 6500}, h.adminContext());
  const {contractId, version} = await readyContract({promoCode: 'BIENVENUE'});
  assert.equal((await db.doc('promo_codes/BIENVENUE').get()).data().uses, 0);
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext());
  assert.equal((await db.doc('promo_codes/BIENVENUE').get()).data().uses, 1);
  assert.match(sent[0].text, /Remise de première année \(code BIENVENUE\) : 65,00 € HT/);
});

test('refus de confirmer : controles incomplets ou non conformes', async () => {
  const {contractId, version} = await readyContract({}, {checks: {...allPass, fraud: {result: 'manual'}}});
  const error = await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'checks_incomplete');
  assert.deepEqual(error.details.missing, ['fraud']);
  assert.equal(sent.length, 0);
  assert.equal((await contract(contractId)).state, 'submitted');
});

test('refus de confirmer : enseigne non rattachee, supprimee ou passee a un tiers', async () => {
  const {contractId: fresh} = await submitMerchantSubscriptionRequestHandler({
    enseigneRequest: {name: 'La Boulangerie', address: '3 place Jean Bart', postalCode: '59140', city: 'Dunkerque'},
    siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId: fresh, expectedVersion: 1, checks: allPass}, h.adminContext());
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId: fresh, expectedVersion: stateVersion}, h.adminContext()), 'enseigne_missing');

  const {contractId, version} = await readyContract();
  await db.doc('enseignes/e1').delete();
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'enseigne_not_owned');
  await h.seedEnseigne('e1', 'other');
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'enseigne_not_owned');
  assert.equal(sent.length, 0);
});

test('refus de confirmer : CGV en vigueur changees depuis l\'acceptation', async () => {
  const {contractId, version} = await readyContract();
  await h.setConfig({cgv: {...h.kCgv, version: '2.2', sha256: 'b'.repeat(64)}});
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'cgv_changed');
  await h.setConfig({cgv: null});
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'cgv_not_configured');
  assert.equal(sent.length, 0);
});

test('PDF des CGV different de l\'empreinte : rien ne part, rien n\'est conclu, le verrou est leve', async () => {
  const {contractId, version} = await readyContract();
  cgvDocument.setLoader(async () => Buffer.from('autre PDF'));
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'cgv_pdf_mismatch');
  assert.equal(sent.length, 0);
  const c = await contract(contractId);
  assert.equal(c.state, 'submitted');
  const i = await internal(contractId);
  assert.ok(!('lock_at' in i.confirmation));
  assert.match(i.confirmation.last_error, /empreinte/);
});

test('echec SMTP : rien n\'est conclu ; nouvel essai sur la version a jour, un seul e-mail', async () => {
  const {contractId, version} = await readyContract();
  h.captureMail(mail, {fail: true});
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'confirmation_failed');
  assert.equal((await contract(contractId)).state, 'submitted');
  sent = h.captureMail(mail);
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()), 'stale_version');
  const current = (await contract(contractId)).state_version;
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: current}, h.adminContext());
  assert.equal((await contract(contractId)).state, 'payment_invited');
  assert.equal(sent.length, 2, 'une confirmation, une invitation');
});

test('reprise : e-mail deja envoye mais contrat non finalise -> finalise sans renvoyer, date = envoi', async () => {
  const {contractId, version} = await readyContract();
  const sentAt = Date.now() - 60000;
  await db.doc(`merchant_contracts/${contractId}/internal/record`).set({confirmation: {
    lock_at: admin.firestore.Timestamp.fromMillis(sentAt), lock_by: 'admin',
    email_sent_at: admin.firestore.Timestamp.fromMillis(sentAt), message_id: '<x@proxiplay.fr>', cgv_sha256: h.kCgvSha256,
  }}, {merge: true});
  const result = await adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext());
  assert.equal(result.confirmedAt, sentAt);
  assert.equal(sent.length, 1, 'aucune seconde confirmation ; seule l\'invitation a payer part');
  assert.match(sent[0].subject, /invitation à régler/);
  assert.equal((await contract(contractId)).confirmed_at.toMillis(), sentAt);
});

test('deux confirmations simultanees : un seul e-mail, un seul contrat conclu', async () => {
  const {contractId, version} = await readyContract();
  const results = await Promise.allSettled([
    adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()),
    adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext()),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(sent.length, 2, 'une confirmation et une invitation, une seule fois');
});

test('apres confirmation : plus de refus possible (art. 4.1) ; admin seul ; refusee : plus de confirmation', async () => {
  const {contractId, version} = await readyContract();
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.merchantContext()), 'permission-denied');
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: version}, h.adminContext());
  const current = (await contract(contractId)).state_version;
  await h.rejectsWith(review.adminRefuseMerchantContractHandler({contractId, expectedVersion: current, motif: 'fraud'}, h.adminContext()), 'not_submitted');
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId, expectedVersion: current}, h.adminContext()), 'not_submitted');
  await h.seedEnseigne('e2', 'merchant');
  const other = await readyContract({enseigneId: 'e2'});
  await review.adminRefuseMerchantContractHandler({contractId: other.contractId, expectedVersion: other.version, motif: 'fraud'}, h.adminContext());
  await h.rejectsWith(adminConfirmMerchantContractHandler({contractId: other.contractId, expectedVersion: other.version + 1}, h.adminContext()), 'not_submitted');
});

test('aucun paiement : la confirmation n\'utilise ni Stripe ni le webhook', () => {
  const source = require('node:fs').readFileSync(require('node:path').join(__dirname, '../merchant_contract_confirm.js'), 'utf8');
  assert.doesNotMatch(source, /require\(["']\.\/(stripe_client|stripe_webhook|merchant_checkout)["']\)/);
});
