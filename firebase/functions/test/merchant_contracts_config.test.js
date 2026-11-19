// Phase 1, tranche 1 (correction) : outil admin de configuration du parcours.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const cgvDocument = require('../merchant_cgv_document');
const {adminUpdateMerchantContractsConfigHandler: update} = require('../merchant_contracts_config');
const {readContractsConfig} = require('../merchant_contracts_model');

const {db} = h;
const cgvInput = {
  version: '2.1', sha256: h.kCgvSha256, storagePath: 'legal/cgv/CGV_V2.1.pdf',
  url: 'https://www.proxiplay.fr/legal-content/sections/CGV.pdf', effectiveDate: '2026-12-01',
};

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.seedAdmin('admin');
  await h.seedMerchant('merchant');
  cgvDocument.setLoader(async () => h.kCgvBytes);
});
test.after(() => cgvDocument.setLoader(null));

const log = async () => (await db.collection('merchant_contracts_config_log').orderBy('at').get()).docs.map((d) => d.data());

test('CGV, adresse des alertes puis ouverture : configuration lue par le parcours, chaque etape journalisee', async () => {
  await update({cgv: cgvInput, adminAlertEmail: 'alertes@proxiplay.test'}, h.adminContext());
  let config = await readContractsConfig(db);
  assert.equal(config.enabled, false, 'fermeture par defaut');
  assert.deepEqual(config.cgv, {version: '2.1', sha256: h.kCgvSha256, storagePath: 'legal/cgv/CGV_V2.1.pdf',
    url: cgvInput.url, effectiveDate: '2026-12-01'});
  assert.equal(config.adminAlertEmail, 'alertes@proxiplay.test');
  await update({enabled: true}, h.adminContext());
  config = await readContractsConfig(db);
  assert.equal(config.enabled, true);
  await update({enabled: false}, h.adminContext());
  assert.equal((await readContractsConfig(db)).enabled, false);
  const entries = await log();
  assert.equal(entries.length, 3);
  assert.deepEqual(entries.map((e) => [e.before.enabled, e.after.enabled]), [[null, null], [null, true], [true, false]]);
  assert.ok(entries.every((e) => e.by === 'admin' && e.at));
  assert.equal(entries[0].after.admin_alert_email, 'alertes@proxiplay.test');
});

test('adresse des alertes configurable ; null revient a l\'adresse par defaut', async () => {
  await update({adminAlertEmail: 'alertes@proxiplay.test'}, h.adminContext());
  assert.equal((await readContractsConfig(db)).adminAlertEmail, 'alertes@proxiplay.test');
  await update({adminAlertEmail: null}, h.adminContext());
  assert.equal((await readContractsConfig(db)).adminAlertEmail, 'contact@proxiplay.fr');
  await h.rejectsWith(update({adminAlertEmail: 'pas-une-adresse'}, h.adminContext()), 'invalid_field');
});

test('ouverture impossible sans CGV ; interrupteur strictement booleen', async () => {
  await h.rejectsWith(update({enabled: true}, h.adminContext()), 'cgv_not_configured');
  await h.rejectsWith(update({enabled: 'true'}, h.adminContext()), 'invalid_field');
  await h.rejectsWith(update({enabled: 1}, h.adminContext()), 'invalid_field');
  await update({cgv: cgvInput}, h.adminContext());
  await h.rejectsWith(update({cgv: null, enabled: true}, h.adminContext()), 'cgv_not_configured');
  assert.equal((await log()).length, 1, 'seule la modification valide est journalisee');
});

test('PDF dans Storage : absent ou d\'une autre empreinte -> refus, rien n\'est ecrit', async () => {
  cgvDocument.setLoader(async () => {
    throw new Error('No such object');
  });
  await h.rejectsWith(update({cgv: cgvInput}, h.adminContext()), 'cgv_pdf_missing');
  cgvDocument.setLoader(async () => Buffer.from('autre PDF'));
  await h.rejectsWith(update({cgv: cgvInput}, h.adminContext()), 'cgv_pdf_mismatch');
  assert.equal((await db.doc('app_config/merchant_contracts').get()).exists, false);
  assert.equal((await log()).length, 0);
});

test('le PDF est reverifie a l\'ouverture : remplace entre-temps -> ouverture refusee', async () => {
  await update({cgv: cgvInput}, h.adminContext());
  cgvDocument.setLoader(async () => Buffer.from('PDF remplace'));
  await h.rejectsWith(update({enabled: true}, h.adminContext()), 'cgv_pdf_mismatch');
  assert.equal((await readContractsConfig(db)).enabled, false);
});

test('validation des CGV : version, empreinte, chemin, adresse https, date', async () => {
  for (const [field, value] of [
    ['version', ''], ['version', 'v 2'], ['sha256', 'abc'], ['storagePath', '../secret.pdf'], ['storagePath', '/legal/cgv.pdf'],
    ['storagePath', 'legal/cgv.docx'], ['url', 'http://www.proxiplay.fr/cgv.pdf'], ['url', 'pas une url'],
    ['effectiveDate', '01/12/2026'], ['effectiveDate', '2026-13-45'],
  ]) {
    await h.rejectsWith(update({cgv: {...cgvInput, [field]: value}}, h.adminContext()), 'invalid_field');
  }
  await h.rejectsWith(update({}, h.adminContext()), 'invalid_field');
});

test('reserve a l\'admin', async () => {
  await h.rejectsWith(update({enabled: false}, h.merchantContext()), 'permission-denied');
  await h.rejectsWith(update({enabled: false}, {}), 'unauthenticated');
});
