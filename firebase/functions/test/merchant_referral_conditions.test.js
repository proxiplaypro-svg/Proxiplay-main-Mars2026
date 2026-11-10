// Conditions du parrainage commercant (1.1.4) : publication par callable
// administrateur seulement, historique immuable, `enabled` jamais modifie,
// parrainages et codes existants intacts. Emulateurs uniquement.
const {test, assert, db, ft, functions, client, assertFails, assertSucceeds} =
  require('./lifecycle_helpers.cjs');
const {
  conditionsVersionAt,
  kDefaultConditionsTitle,
  kInitialConditionsText,
  parseConditionsText,
  publishMerchantReferralConditions,
  validateConditions,
} = require('../merchant_referral_conditions');

const configPath = 'app_config/merchant_referral';
const publish = ft.wrap(functions.adminPublishMerchantReferralConditions);
const asAdmin = {auth: {uid: 'operator', token: {}}};
const reason = 'Version initiale validee';

async function resetConfig(data = {enabled: false}) {
  const versions = await db.collection(`${configPath}/conditions_versions`).get();
  await Promise.all(versions.docs.map((doc) => doc.ref.delete()));
  if (data === null) await db.doc(configPath).delete();
  else await db.doc(configPath).set(data);
}

async function rejectsWith(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, error.message);
    return true;
  });
}

test('le texte initial est valide et decoupe en paragraphes et liste', () => {
  const checked = validateConditions({title: kDefaultConditionsTitle, text: kInitialConditionsText});
  assert.deepEqual(checked.errors, []);
  const lists = checked.blocks.filter((block) => block.type === 'list');
  assert.equal(lists.length, 1);
  assert.equal(lists[0].items.length, 6);
  assert.equal(lists[0].items[5], 'Un commerçant ne peut pas se parrainer lui-même.');
  assert.equal(checked.blocks.length, 7);
});

test('validation : texte trop court, HTML, titre vide, caracteres de controle', () => {
  assert.ok(validateConditions({title: 'T', text: 'court'}).errors.length);
  assert.ok(validateConditions({title: 'T', text: kInitialConditionsText + '\n\n<script>x</script>'}).errors.length);
  assert.ok(validateConditions({title: ' ', text: kInitialConditionsText}).errors.length);
  assert.ok(validateConditions({title: 'T', text: kInitialConditionsText + '\u0007'}).errors.length);
  assert.ok(validateConditions({title: 'A\nB', text: kInitialConditionsText}).errors.length);
  assert.deepEqual(parseConditionsText('a\r\nb\r\n\r\n- c\r\n- d'),
    [{type: 'paragraph', text: 'a b'}, {type: 'list', items: ['c', 'd']}]);
});

test('publication : version 1, historique, enabled et autres champs intacts', async () => {
  await resetConfig({enabled: false, autre_reglage: 'conserve'});
  const result = await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  assert.deepEqual(result, {status: 'published', version: 1});

  const config = (await db.doc(configPath).get()).data();
  assert.equal(config.enabled, false);
  assert.equal(config.autre_reglage, 'conserve');
  assert.equal(config.conditions.version, 1);
  assert.equal(config.conditions.format, 'plain_v1');
  assert.equal(config.conditions.title, kDefaultConditionsTitle);
  assert.equal(config.conditions.text, kInitialConditionsText);
  assert.ok(config.conditions.effective_at.toMillis() > 0);
  assert.ok(config.conditions.updated_at.toMillis() > 0);

  const history = (await db.doc(`${configPath}/conditions_versions/1`).get()).data();
  assert.equal(history.text, kInitialConditionsText);
  assert.equal(history.published_by, 'users/operator');
  assert.equal(history.reason, reason);
  assert.equal(history.previous_version, null);
});

test('nouvelle version : affichee a la place, ancienne conservee dans l historique', async () => {
  await resetConfig({enabled: true});
  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  const v2 = kInitialConditionsText.replace('ProxiPlay peut refuser', 'ProxiPlay se reserve le droit de refuser');
  const result = await publish({text: v2, reason: 'Precision juridique', expectedVersion: 1}, asAdmin);
  assert.equal(result.version, 2);

  const config = (await db.doc(configPath).get()).data();
  assert.equal(config.enabled, true);
  assert.equal(config.conditions.version, 2);
  assert.match(config.conditions.text, /se reserve le droit/);
  const versions = await db.collection(`${configPath}/conditions_versions`).orderBy('version').get();
  assert.deepEqual(versions.docs.map((doc) => doc.data().version), [1, 2]);
  assert.equal(versions.docs[0].data().text, kInitialConditionsText);
  assert.equal(versions.docs[1].data().previous_version, 1);
});

test('conflit de version : rien n est ecrit', async () => {
  await resetConfig();
  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin), 'aborted');
  const versions = await db.collection(`${configPath}/conditions_versions`).get();
  assert.equal(versions.size, 1);
});

test('apercu (dryRun) : blocs renvoyes, aucune ecriture', async () => {
  await resetConfig();
  const preview = await publish({text: kInitialConditionsText, reason, expectedVersion: 0, dryRun: true}, asAdmin);
  assert.equal(preview.status, 'preview');
  assert.equal(preview.version, 1);
  assert.equal(preview.blocks.length, 7);
  assert.equal((await db.doc(configPath).get()).data().conditions, undefined);
  assert.equal((await db.collection(`${configPath}/conditions_versions`).get()).size, 0);
});

test('jamais d activation involontaire : document absent ou sans enabled refuse', async () => {
  await resetConfig(null);
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin),
    'failed-precondition');
  assert.equal((await db.doc(configPath).get()).exists, false);

  await resetConfig({autre: 1});
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin),
    'failed-precondition');
  assert.deepEqual((await db.doc(configPath).get()).data(), {autre: 1});

  await resetConfig({enabled: 'false'});
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin),
    'failed-precondition');
});

test('publication refusee : non connecte, joueur, commercant, donnees invalides', async () => {
  await resetConfig();
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0}, {}), 'unauthenticated');
  for (const uid of ['player', 'merchant']) {
    await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: 0},
      {auth: {uid, token: {}}}), 'permission-denied');
  }
  await rejectsWith(publish({text: 'trop court', reason, expectedVersion: 0}, asAdmin), 'invalid-argument');
  await rejectsWith(publish({text: kInitialConditionsText, reason: '', expectedVersion: 0}, asAdmin), 'invalid-argument');
  await rejectsWith(publish({text: kInitialConditionsText, reason, expectedVersion: -1}, asAdmin), 'invalid-argument');
  assert.equal((await db.doc(configPath).get()).data().conditions, undefined);
});

test('regles : aucun client n ecrit les conditions ni l historique', async () => {
  await resetConfig({enabled: false});
  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  const tampered = {conditions: {version: 9, format: 'plain_v1', title: 'X', text: 'Faux'}};
  for (const uid of ['player', 'merchant', 'operator']) {
    await assertFails(client(uid).doc(configPath).set(tampered, {merge: true}));
    await assertFails(client(uid).doc(configPath).update({'conditions.text': 'Faux'}));
    await assertFails(client(uid).doc(`${configPath}/conditions_versions/1`).set({text: 'Faux'}));
    await assertFails(client(uid).doc(`${configPath}/conditions_versions/2`).set({text: 'Faux'}));
    await assertFails(client(uid).doc(`${configPath}/conditions_versions/1`).delete());
    await assertFails(client(uid).doc(configPath).delete());
  }
  assert.equal((await db.doc(configPath).get()).data().conditions.text, kInitialConditionsText);
});

test('regles : l interrupteur Admin reste possible, toujours booleen', async () => {
  await resetConfig({enabled: false});
  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  const admin = client('operator').doc(configPath);
  await assertSucceeds(admin.set({enabled: true}, {merge: true}));
  await assertSucceeds(admin.set({enabled: false}, {merge: true}));
  await assertFails(admin.set({enabled: 'true'}, {merge: true}));
  await assertFails(admin.update({enabled: null}));
  await assertFails(admin.set({enabled: true})); // ecrasement complet : conditions perdues
  await assertFails(client('player').doc(configPath).set({enabled: true}, {merge: true}));
  await assertFails(client('merchant').doc(configPath).set({enabled: true}, {merge: true}));
  const config = (await db.doc(configPath).get()).data();
  assert.equal(config.enabled, false);
  assert.equal(config.conditions.version, 1);

  // Creation par l'Admin quand le document n'existe pas : enabled seul.
  await resetConfig(null);
  await assertFails(admin.set({enabled: true, conditions: {version: 1}}));
  await assertSucceeds(admin.set({enabled: false}, {merge: true}));
});

test('regles : lecture des conditions et de l historique', async () => {
  await resetConfig({enabled: false});
  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  for (const uid of ['player', 'merchant', 'operator']) {
    await assertSucceeds(client(uid).doc(configPath).get());
    await assertSucceeds(client(uid).doc(`${configPath}/conditions_versions/1`).get());
  }
});

test('anciens parrainages, codes et recompenses : jamais modifies par une publication', async () => {
  await resetConfig({enabled: true});
  const referral = {
    merchant_user_id: db.doc('users/merchant'), inviter_user_id: db.doc('users/player'),
    code: 'ABCD2345', status: 'approved', reward_amount_cents: 5000,
    linked_at: new Date('2026-10-01T10:00:00Z'),
  };
  await db.doc('merchant_referrals/merchant').set(referral);
  await db.doc('merchant_referral_codes/ABCD2345').set({inviter_user_id: db.doc('users/player')});
  const before = (await db.doc('merchant_referrals/merchant').get()).data();

  await publish({text: kInitialConditionsText, reason, expectedVersion: 0}, asAdmin);
  await publish({text: kInitialConditionsText.replace('ProxiPlay peut', 'ProxiPlay pourra'),
    reason: 'Deuxieme version', expectedVersion: 1}, asAdmin);

  assert.deepEqual((await db.doc('merchant_referrals/merchant').get()).data(), before);
  assert.ok((await db.doc('merchant_referral_codes/ABCD2345').get()).exists);
  assert.equal((await db.doc(configPath).get()).data().enabled, true);
  await db.doc('merchant_referrals/merchant').delete();
  await db.doc('merchant_referral_codes/ABCD2345').delete();
});

test('version applicable a un parrainage : celle en vigueur a son enregistrement', () => {
  const at = (iso) => ({toMillis: () => Date.parse(iso)});
  const versions = [
    {version: 1, effective_at: at('2026-11-15T00:00:00Z')},
    {version: 2, effective_at: at('2027-01-10T00:00:00Z')},
  ];
  assert.equal(conditionsVersionAt(versions, new Date('2026-10-01T00:00:00Z')), null);
  assert.equal(conditionsVersionAt(versions, new Date('2026-12-01T00:00:00Z')).version, 1);
  assert.equal(conditionsVersionAt(versions, at('2027-02-01T00:00:00Z')).version, 2);
  assert.equal(conditionsVersionAt(versions, null), null);
});

test('publishMerchantReferralConditions ne cree jamais le document', async () => {
  await resetConfig(null);
  const result = await publishMerchantReferralConditions(db, {
    text: kInitialConditionsText, reason, expectedVersion: 0, publishedBy: 'script',
  });
  assert.equal(result.status, 'config_missing_enabled');
  assert.equal((await db.doc(configPath).get()).exists, false);
});
