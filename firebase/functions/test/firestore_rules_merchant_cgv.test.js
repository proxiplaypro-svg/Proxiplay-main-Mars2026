#!/usr/bin/env node

// Règles inchangées : l'acceptation des CGV ne peut être écrite que par le
// serveur. Émulateur Firestore uniquement :
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_merchant_cgv.test.js"
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');

const [emulatorHost, emulatorPort] = (process.env.FIRESTORE_EMULATOR_HOST || '').split(':');
if (!emulatorHost || !/^\d+$/.test(emulatorPort || '')) throw new Error('FIRESTORE_EMULATOR_HOST requis (hôte:port) : aucun accès production n’est autorisé.');

let testEnv;
test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-proxiplay-rules-merchant-cgv',
    firestore: {
      rules: fs.readFileSync(process.env.FIRESTORE_RULES_FILE || path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: emulatorHost,
      port: Number(emulatorPort),
    },
  });
  await testEnv.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await db.doc('users/merchant_uid').set({uid: 'merchant_uid', user_role: 'commercant', email: 'm@example.test', first_name: 'Camille'});
    await db.doc('merchant_cgv_acceptances/merchant_uid/history/2.1').set({uid: 'merchant_uid', cgv_version: '2.1', source: 'signup'});
  });
});
test.after(async () => { await testEnv.cleanup(); });

const merchantDb = () => testEnv.authenticatedContext('merchant_uid').firestore();

test('contrôle : le commerçant peut toujours modifier un champ de profil autorisé', async () => {
  await assertSucceeds(merchantDb().doc('users/merchant_uid').update({first_name: 'Camille B.'}));
});

test('le commerçant ne peut pas écrire cgv_accepted_version ni cgv_accepted_at dans sa fiche', async () => {
  const user = merchantDb().doc('users/merchant_uid');
  await assertFails(user.update({cgv_accepted_version: '2.1'}));
  await assertFails(user.update({cgv_accepted_at: new Date()}));
  await assertFails(user.set({cgv_accepted_version: '2.1'}, {merge: true}));
});

test('le commerçant ne peut ni lire ni écrire merchant_cgv_acceptances/**', async () => {
  const db = merchantDb();
  await assertFails(db.doc('merchant_cgv_acceptances/merchant_uid').get());
  await assertFails(db.doc('merchant_cgv_acceptances/merchant_uid/history/2.1').get());
  await assertFails(db.collection('merchant_cgv_acceptances/merchant_uid/history').get());
  await assertFails(db.doc('merchant_cgv_acceptances/merchant_uid/history/2.2').set({uid: 'merchant_uid', cgv_version: '2.2'}));
  await assertFails(db.doc('merchant_cgv_acceptances/merchant_uid/history/2.1').update({source: 'login'}));
  await assertFails(db.doc('merchant_cgv_acceptances/merchant_uid').set({x: 1}));
  await assertFails(testEnv.unauthenticatedContext().firestore().doc('merchant_cgv_acceptances/merchant_uid/history/2.1').get());
});

// Écart connu (non corrigé ici, firestore.rules hors périmètre) : la règle de
// CRÉATION de users/{uid} (isAllowedSelfUserCreate) fonctionne par liste noire
// et n'interdit pas cgv_accepted_version. Un client peut donc poser ce champ
// en créant sa propre fiche. L'Admin s'appuie pour cette raison sur la trace
// serveur merchant_cgv_acceptances/{uid}/history, pas sur ce champ.
test.todo('création de users/{uid} : refuser cgv_accepted_version / cgv_accepted_at (règles à compléter)');
