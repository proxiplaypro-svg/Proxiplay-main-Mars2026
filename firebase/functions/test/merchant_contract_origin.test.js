// Phase 1, tranche 1, lot 1.4b : origine (art. 4.2) et signalement de visite.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const {submitMerchantSubscriptionRequestHandler, previewMerchantContractHandler, adminUpsertPromoCodeHandler} =
  require('../merchant_contracts_request');
const origin = require('../merchant_contract_origin');
const paris = require('../paris_time');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
let sent;

function request(overrides = {}) {
  return {
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
    ...overrides,
  };
}

async function contractOf(result) {
  const [main, internal] = await Promise.all([
    db.doc(`merchant_contracts/${result.contractId}`).get(),
    db.doc(`merchant_contracts/${result.contractId}/internal/record`).get(),
  ]);
  return {main: main.data(), internal: internal.data()};
}

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  sent = h.captureMail(mail);
});
test.after(() => mail.setSender(null));

test('sans lien, sans code de commercial, sans case : spontanee', async () => {
  const {main, internal} = await contractOf(await submitMerchantSubscriptionRequestHandler(request(), h.merchantContext()));
  assert.equal(main.origin.type, 'spontanee');
  assert.deepEqual(internal.origin_evidence.sources, []);
});

test('lien nominatif valide : demarchee, commercial et date de commande enregistres, jeton jamais stocke', async () => {
  const {repId} = await origin.adminUpsertSalesRepHandler({name: 'Alex Commercial', email: 'alex@example.test'}, h.adminContext());
  const link = await origin.adminCreateRepLinkHandler({repId, enseigneName: 'Boutique e1', siret: '988 968 376 00018', sentAt: '2026-11-20T10:00:00Z'}, h.adminContext());
  assert.match(link.token, origin.kTokenPattern);
  assert.equal(link.path, `/espace-commercant/?lien=${link.token}`);
  const links = await db.collection('rep_links').get();
  assert.deepEqual(links.docs.map((d) => d.id), [origin.hashToken(link.token)]);
  assert.ok(!JSON.stringify(links.docs[0].data()).includes(link.token), 'le jeton en clair n\'est jamais stocke');
  assert.equal(links.docs[0].data().sent_at.toDate().toISOString(), '2026-11-20T10:00:00.000Z');

  const preview = await previewMerchantContractHandler({offerId: 'autonome', repLinkToken: link.token}, h.merchantContext());
  assert.equal(preview.origin, 'demarchee');
  assert.deepEqual(preview.prefill, {enseigneName: 'Boutique e1', siret: '98896837600018'});

  const result = await submitMerchantSubscriptionRequestHandler(request({repLinkToken: link.token}), h.merchantContext());
  const {main, internal} = await contractOf(result);
  assert.equal(main.origin.type, 'demarchee');
  assert.deepEqual(internal.origin_evidence.sources, ['link']);
  assert.equal(internal.origin_evidence.rep_id, repId);
  assert.ok(!JSON.stringify(main).includes(repId), 'le commercial reste une donnee interne');
  const used = (await db.doc(`rep_links/${origin.hashToken(link.token)}`).get()).data();
  assert.equal(used.uses, 1);
  assert.ok(used.first_used_at);
  assert.equal(used.last_contract_id, result.contractId);
});

test('doute (lien non reconnu ou mal forme) : regime le plus favorable, demarchee', async () => {
  for (const token of ['x'.repeat(32), 'court', '../../etc']) {
    await h.clearFirestore();
    await h.setConfig();
    await h.seedMerchant('merchant');
    await h.seedEnseigne('e1', 'merchant');
    const {main, internal} = await contractOf(await submitMerchantSubscriptionRequestHandler(request({repLinkToken: token}), h.merchantContext()));
    assert.equal(main.origin.type, 'demarchee', token);
    assert.deepEqual(internal.origin_evidence.sources, ['link_unrecognized']);
  }
});

test('code promotionnel remis par un commercial : demarchee ; code sans commercial : spontanee', async () => {
  const {repId} = await origin.adminUpsertSalesRepHandler({name: 'Alex Commercial'}, h.adminContext());
  await adminUpsertPromoCodeHandler({code: 'ALEX10', kind: 'percent', value: 10, repId}, h.adminContext());
  await adminUpsertPromoCodeHandler({code: 'SITE10', kind: 'percent', value: 10}, h.adminContext());
  await h.rejectsWith(adminUpsertPromoCodeHandler({code: 'FAUX', kind: 'percent', value: 10, repId: 'inconnu'}, h.adminContext()), 'invalid_field');
  const rep = await contractOf(await submitMerchantSubscriptionRequestHandler(request({promoCode: 'ALEX10'}), h.merchantContext()));
  assert.equal(rep.main.origin.type, 'demarchee');
  assert.deepEqual(rep.internal.origin_evidence.sources, ['code']);
  assert.equal(rep.internal.origin_evidence.code, 'ALEX10');
  await h.seedEnseigne('e2', 'merchant');
  const site = await contractOf(await submitMerchantSubscriptionRequestHandler(request({enseigneId: 'e2', promoCode: 'SITE10'}), h.merchantContext()));
  assert.equal(site.main.origin.type, 'spontanee');
});

test('case « j\'ai recu la visite d\'un representant » : demarchee ; seul le booleen true compte', async () => {
  const declared = await contractOf(await submitMerchantSubscriptionRequestHandler(request({visitDeclared: true}), h.merchantContext()));
  assert.equal(declared.main.origin.type, 'demarchee');
  assert.deepEqual(declared.internal.origin_evidence.sources, ['declaration']);
  await h.seedEnseigne('e2', 'merchant');
  const notDeclared = await contractOf(await submitMerchantSubscriptionRequestHandler(request({enseigneId: 'e2', visitDeclared: 'on'}), h.merchantContext()));
  assert.equal(notDeclared.main.origin.type, 'spontanee');
});

test('signalement avant la confirmation : demarchee, journal, e-mails ; idempotent', async () => {
  const {contractId} = await submitMerchantSubscriptionRequestHandler(request(), h.merchantContext());
  sent.length = 0;
  assert.deepEqual(await origin.reportMerchantVisitHandler({contractId}, h.merchantContext()), {origin: 'demarchee', changed: true});
  const {main, internal} = await contractOf({contractId});
  assert.equal(main.origin.type, 'demarchee');
  assert.ok(main.origin.reported_at);
  assert.equal(main.state_version, 2);
  assert.deepEqual(internal.origin_evidence.sources, ['report']);
  assert.equal(internal.origin_evidence.report.previous_type, 'spontanee');
  const events = await db.collection(`merchant_contracts/${contractId}/events`).get();
  assert.deepEqual(events.docs.map((d) => d.data().type).sort(), ['submitted', 'visit_reported']);
  assert.deepEqual(sent.map((m) => m.to), ['merchant@example.test', 'alertes@proxiplay.test']);
  assert.match(sent[0].text, /désormais traitée comme démarchée/);
  assert.match(sent[0].text, /sommes déjà versées sont remboursées en cas de rétractation/);
  assert.doesNotMatch(sent[0].text, /Me rétracter/, 'la fonction en ligne arrive en tranche 2');
  assert.deepEqual(await origin.reportMerchantVisitHandler({contractId}, h.merchantContext()), {origin: 'demarchee', changed: false});
  assert.equal(sent.length, 2, 'aucun nouvel e-mail');
});

async function seedConfirmed(id, confirmedAtMs, extra = {}) {
  await db.doc(`merchant_contracts/${id}`).set({
    owner_uid: 'merchant', owner_email: 'merchant@example.test', state: 'confirmed', state_version: 3,
    enseigne_id: 'e1', enseigne_name: 'Boutique e1', origin: {type: 'spontanee'},
    confirmed_at: Timestamp.fromMillis(confirmedAtMs),
    visit_report_deadline: Timestamp.fromMillis(paris.visitReportDeadline(confirmedAtMs)), ...extra,
  });
}

test('apres la conclusion : possible jusqu\'a la fin du 14e jour suivant (Paris), refuse ensuite', async () => {
  const now = Date.now();
  await seedConfirmed('recent', now - 13 * 86400000);
  assert.equal((await origin.reportMerchantVisitHandler({contractId: 'recent'}, h.merchantContext())).changed, true);
  await seedConfirmed('ancien', now - 16 * 86400000);
  await h.rejectsWith(origin.reportMerchantVisitHandler({contractId: 'ancien'}, h.merchantContext()), 'report_deadline_passed');
  assert.equal((await db.doc('merchant_contracts/ancien').get()).data().origin.type, 'spontanee');
});

test('signalement refuse : demande refusee, demande d\'un autre compte, demande inconnue', async () => {
  await db.doc('merchant_contracts/refusee').set({owner_uid: 'merchant', state: 'refused', origin: {type: 'spontanee'}});
  await h.rejectsWith(origin.reportMerchantVisitHandler({contractId: 'refusee'}, h.merchantContext()), 'not_reportable');
  await seedConfirmed('autre', Date.now(), {owner_uid: 'other'});
  await h.rejectsWith(origin.reportMerchantVisitHandler({contractId: 'autre'}, h.merchantContext()), 'contract_not_found');
  await h.rejectsWith(origin.reportMerchantVisitHandler({contractId: 'absente'}, h.merchantContext()), 'contract_not_found');
});

test('delai de 14 jours : fin de journee a Paris, changements d\'heure compris', () => {
  // Conclusion le 15 mars 2026 a 10 h (Paris, UTC+1) ; 29 mars = passage a l'heure d'ete.
  assert.equal(new Date(paris.visitReportDeadline(Date.UTC(2026, 2, 15, 9))).toISOString(), '2026-03-29T21:59:59.999Z');
  // Conclusion le 1er decembre 2026 : 15 decembre 23:59:59.999 (UTC+1).
  assert.equal(new Date(paris.visitReportDeadline(Date.UTC(2026, 11, 1, 15))).toISOString(), '2026-12-15T22:59:59.999Z');
  // 10 janvier 23 h 30 a Paris (22 h 30 UTC) : le jour de conclusion est le 10, pas le 11.
  assert.equal(new Date(paris.visitReportDeadline(Date.UTC(2026, 0, 10, 22, 30))).toISOString(), '2026-01-24T22:59:59.999Z');
  // 10 janvier 23 h 30 UTC = 11 janvier 0 h 30 a Paris.
  assert.equal(new Date(paris.visitReportDeadline(Date.UTC(2026, 0, 10, 23, 30))).toISOString(), '2026-01-25T22:59:59.999Z');
});

test('commerciaux et liens : admin seul ; lien pour un commercial desactive refuse', async () => {
  await h.rejectsWith(origin.adminUpsertSalesRepHandler({name: 'X Y'}, h.merchantContext()), 'permission-denied');
  await h.rejectsWith(origin.adminCreateRepLinkHandler({repId: 'r'}, h.merchantContext()), 'permission-denied');
  const {repId} = await origin.adminUpsertSalesRepHandler({name: 'Ancien commercial', active: false}, h.adminContext());
  await h.rejectsWith(origin.adminCreateRepLinkHandler({repId}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(origin.adminUpsertSalesRepHandler({name: 'Z', email: 'pas-un-email'}, h.adminContext()), 'invalid_field');
});
