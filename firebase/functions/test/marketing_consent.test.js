#!/usr/bin/env node

// Runs only against a Firestore emulator. It calls the Callable handler
// directly so that the transaction and server timestamps are tested without
// any production credential or access.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('FIRESTORE_EMULATOR_HOST requis : aucun accès production n’est autorisé.');
}

const projectId = process.env.GCLOUD_PROJECT || 'proxi-play-marketing-consent';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = admin.firestore();
const callable = require('../marketing_consent').setMarketingConsent;

let sequence = 0;
function nextUid() {
  sequence += 1;
  return `marketing_test_${sequence}`;
}

async function createPlayer(uid, birthday) {
  const player = {uid, user_role: 'joueur'};
  if (birthday) player.birthday = admin.firestore.Timestamp.fromDate(birthday);
  await db.doc(`users/${uid}`).set(player);
}

async function call(data, uid) {
  return callable.run(data, uid ? {auth: {uid}} : {});
}

async function expectHttpsError(promise, code) {
  await assert.rejects(promise, error => error && error.code === code);
}

test('refuse un appel non authentifié sans écrire', async () => {
  await expectHttpsError(
    call({enabled: true, textVersion: 'marketing-player-v1', source: 'signup'}),
    'unauthenticated',
  );
});

test('refuse les paramètres invalides sans écriture', async () => {
  const uid = nextUid();
  await createPlayer(uid, new Date('1990-01-01T00:00:00Z'));
  await expectHttpsError(call({enabled: 'true', textVersion: 'marketing-player-v1', source: 'signup'}, uid), 'invalid-argument');
  await expectHttpsError(call({enabled: true, textVersion: 'other-version', source: 'signup'}, uid), 'invalid-argument');
  const events = await db.doc(`users/${uid}`).collection('marketing_consent_events').get();
  assert.equal(events.size, 0);
  assert.equal((await db.doc(`users/${uid}`).get()).data().marketing_consent, undefined);
});

test('enregistre atomiquement une acceptation avec horodatages serveur', async () => {
  const uid = nextUid();
  await createPlayer(uid, new Date('1990-01-01T00:00:00Z'));
  assert.deepEqual(await call({enabled: true, textVersion: 'marketing-player-v1', source: 'signup'}, uid), {enabled: true});
  const user = (await db.doc(`users/${uid}`).get()).data();
  const events = await db.doc(`users/${uid}`).collection('marketing_consent_events').get();
  assert.equal(events.size, 1);
  const event = events.docs[0].data();
  assert.equal(user.marketing_consent.enabled, true);
  assert.equal(user.marketing_consent.text_version, 'marketing-player-v1');
  assert.equal(user.marketing_consent.newsletter_eligibility, 'age_15_plus_confirmed');
  assert.equal(event.event_type, 'granted');
  assert.ok(user.marketing_consent.updated_at?.toDate instanceof Function);
  assert.ok(event.updated_at?.toDate instanceof Function);
  assert.ok(event.retention_until?.toDate instanceof Function);
});

test('enregistre un retrait et conserve la preuve antérieure', async () => {
  const uid = nextUid();
  await createPlayer(uid, new Date('1990-01-01T00:00:00Z'));
  await call({enabled: true, textVersion: 'marketing-player-v1', source: 'signup'}, uid);
  await call({enabled: false, textVersion: 'marketing-player-v1', source: 'player-profile'}, uid);
  const user = (await db.doc(`users/${uid}`).get()).data();
  const events = await db.doc(`users/${uid}`).collection('marketing_consent_events').get();
  assert.equal(user.marketing_consent.enabled, false);
  assert.equal(user.marketing_consent.newsletter_eligibility, 'not_subscribed');
  assert.deepEqual(events.docs.map(doc => doc.data().event_type).sort(), ['granted', 'withdrawn']);
});

test('refuse une acceptation non éligible sans écriture partielle', async () => {
  const uid = nextUid();
  await createPlayer(uid, new Date('2015-01-01T00:00:00Z'));
  await expectHttpsError(call({enabled: true, textVersion: 'marketing-player-v1', source: 'signup'}, uid), 'failed-precondition');
  const user = (await db.doc(`users/${uid}`).get()).data();
  const events = await db.doc(`users/${uid}`).collection('marketing_consent_events').get();
  assert.equal(user.marketing_consent, undefined);
  assert.equal(events.size, 0);
});

test('exclut un âge non établissable sans créer de consentement', async () => {
  const uid = nextUid();
  await createPlayer(uid);
  await expectHttpsError(call({enabled: true, textVersion: 'marketing-player-v1', source: 'signup'}, uid), 'failed-precondition');
  const user = (await db.doc(`users/${uid}`).get()).data();
  const events = await db.doc(`users/${uid}`).collection('marketing_consent_events').get();
  assert.equal(user.marketing_consent, undefined);
  assert.equal(events.size, 0);
});
