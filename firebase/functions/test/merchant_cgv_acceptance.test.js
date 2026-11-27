#!/usr/bin/env node

// recordMerchantCgvAcceptance, contre les émulateurs Firestore et Auth
// uniquement : le handler est appelé directement (transaction et heure
// serveur réelles), sans aucun accès production.
//
//   firebase emulators:exec --only firestore,auth \
//     "node --test test/merchant_cgv_acceptance.test.js"
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const local = /^(localhost|127\.0\.0\.1|0\.0\.0\.0):\d+$/;
if (!local.test(process.env.FIRESTORE_EMULATOR_HOST || '') || !local.test(process.env.FIREBASE_AUTH_EMULATOR_HOST || '')) {
  throw new Error('FIRESTORE_EMULATOR_HOST et FIREBASE_AUTH_EMULATOR_HOST locaux requis : aucun accès production n’est autorisé.');
}

const projectId = process.env.GCLOUD_PROJECT || 'demo-proxiplay-merchant-cgv';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = admin.firestore();
const {recordMerchantCgvAcceptance: callable, _constants} = require('../merchant_cgv_acceptance');

let sequence = 0;
async function createAccount(role) {
  sequence += 1;
  const uid = `cgv_test_${Date.now()}_${sequence}`;
  const email = `${uid}@example.test`;
  await admin.auth().createUser({uid, email});
  await db.doc(`users/${uid}`).set({uid, email, user_role: role});
  return {uid, email};
}

function call(data, uid, userAgent = 'ProxiPlay/1.1.4 (test)') {
  return callable.run(data, uid ? {auth: {uid}, rawRequest: {headers: {'user-agent': userAgent}}} : {});
}

async function expectHttpsError(promise, code) {
  await assert.rejects(promise, error => error && error.code === code);
}

async function historyOf(uid) {
  return db.collection(`merchant_cgv_acceptances/${uid}/history`).get();
}

test('refuse un appel non authentifié', async () => {
  await expectHttpsError(call({accepted: true, source: 'signup'}), 'unauthenticated');
});

test('refuse un joueur sans rien écrire', async () => {
  const {uid} = await createAccount('joueur');
  await expectHttpsError(call({accepted: true, source: 'signup'}, uid), 'permission-denied');
  assert.equal((await historyOf(uid)).size, 0);
  assert.equal((await db.doc(`users/${uid}`).get()).get('cgv_accepted_version'), undefined);
});

test('refuse accepted absent, faux ou non booléen, et une origine invalide', async () => {
  const {uid} = await createAccount('commercant');
  for (const data of [{source: 'signup'}, {accepted: false, source: 'signup'}, {accepted: 'true', source: 'login'}, null]) {
    await expectHttpsError(call(data, uid), 'invalid-argument');
  }
  await expectHttpsError(call({accepted: true, source: 'other'}, uid), 'invalid-argument');
  assert.equal((await historyOf(uid)).size, 0);
  assert.equal((await db.doc(`users/${uid}`).get()).get('cgv_accepted_version'), undefined);
});

test('commerçant : fiche et trace history/2.1 écrites avec l’heure serveur', async () => {
  const {uid, email} = await createAccount('commercant');
  const before = Date.now();
  assert.deepEqual(await call({accepted: true, source: 'signup'}, uid, 'x'.repeat(500)), {accepted: true, version: '2.1'});
  const user = (await db.doc(`users/${uid}`).get()).data();
  assert.equal(user.cgv_accepted_version, '2.1');
  assert.ok(user.cgv_accepted_at instanceof admin.firestore.Timestamp);
  assert.ok(Math.abs(user.cgv_accepted_at.toMillis() - before) < 60000);
  const history = await historyOf(uid);
  assert.deepEqual(history.docs.map(doc => doc.id), ['2.1']);
  const trace = history.docs[0].data();
  assert.deepEqual(Object.keys(trace).sort(), ['accepted_at', 'cgv_version', 'checkbox_text', 'email', 'source', 'uid', 'user_agent']);
  assert.equal(trace.uid, uid);
  assert.equal(trace.email, email);
  assert.equal(trace.cgv_version, '2.1');
  assert.equal(trace.checkbox_text, _constants.kMerchantCgvCheckboxText);
  assert.equal(trace.source, 'signup');
  assert.equal(trace.user_agent.length, 300);
  assert.ok(trace.accepted_at.isEqual(user.cgv_accepted_at));
});

test('deuxième appel : pas de doublon, date et origine d’origine conservées', async () => {
  const {uid} = await createAccount('commercant');
  await call({accepted: true, source: 'signup'}, uid);
  const first = (await db.doc(`merchant_cgv_acceptances/${uid}/history/2.1`).get()).data();
  const firstUser = (await db.doc(`users/${uid}`).get()).data();
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.deepEqual(await call({accepted: true, source: 'login'}, uid), {accepted: true, version: '2.1'});
  const history = await historyOf(uid);
  assert.equal(history.size, 1);
  const second = history.docs[0].data();
  assert.ok(second.accepted_at.isEqual(first.accepted_at));
  assert.equal(second.source, 'signup');
  assert.ok((await db.doc(`users/${uid}`).get()).get('cgv_accepted_at').isEqual(firstUser.cgv_accepted_at));
});

test('aucune adresse IP enregistrée', async () => {
  const {uid} = await createAccount('commercant');
  await callable.run({accepted: true, source: 'login'}, {auth: {uid}, rawRequest: {ip: '203.0.113.7', headers: {'user-agent': 'UA', 'x-forwarded-for': '203.0.113.7'}}});
  const trace = JSON.stringify((await db.doc(`merchant_cgv_acceptances/${uid}/history/2.1`).get()).data());
  assert.equal(trace.includes('203.0.113.7'), false);
});

test('texte, version et lien identiques aux constantes de l’app (lib/utils/merchant_cgv.dart)', () => {
  const dart = fs.readFileSync(path.resolve(__dirname, '../../../lib/utils/merchant_cgv.dart'), 'utf8');
  const constant = name => {
    const match = dart.match(new RegExp(`const\\s+${name}\\s*=\\s*"([^"]*)";`));
    assert.ok(match, `${name} introuvable dans merchant_cgv.dart`);
    return match[1];
  };
  assert.equal(constant('kMerchantCgvVersion'), _constants.kMerchantCgvVersion);
  assert.equal(constant('kMerchantCgvCheckboxText'), _constants.kMerchantCgvCheckboxText);
  assert.equal(constant('kMerchantCgvUrl'), _constants.kMerchantCgvUrl);
  assert.equal(
    _constants.kMerchantCgvCheckboxText,
    'J\'ai lu et j\'accepte les conditions générales de vente PROXIPLAY (version 2.1, applicables à compter du 1er décembre 2026).',
  );
});
