// Authenticity of the Google ID token sent with a referral signup
// (verifyGoogleIdToken): Google signature, issuer, audience, expiry and
// verified address, checked before any account lookup. Tokens are signed
// here with a local key passed as the published Google keys.
// Isolated demo emulators only (the module loads Firestore).
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const {verifyGoogleIdToken, kGoogleIdTokenAudiences} = require('../lib/share_promo/new_account_referral');

const google = crypto.generateKeyPairSync('rsa', {modulusLength: 2048});
const attacker = crypto.generateKeyPairSync('rsa', {modulusLength: 2048});
const certs = {'google-key': google.publicKey.export({type: 'spki', format: 'pem'})};
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = () => Math.floor(Date.now() / 1000);
function jwt(claims = {}, {key = google.privateKey, kid = 'google-key', alg = 'RS256'} = {}) {
  const payload = {iss: 'https://accounts.google.com', aud: kGoogleIdTokenAudiences[0], sub: 'g-123',
    email: 'Player@Gmail.test', email_verified: true, iat: now() - 10, exp: now() + 3000, ...claims};
  const signed = `${b64({alg, kid, typ: 'JWT'})}.${b64(payload)}`;
  if (alg === 'none') return `${signed}.`;
  return `${signed}.${crypto.sign('RSA-SHA256', Buffer.from(signed), key).toString('base64url')}`;
}

test('an authentic token for the Android or iOS client gives its verified identity', async () => {
  assert.deepEqual(await verifyGoogleIdToken(jwt(), certs), {sub: 'g-123', email: 'player@gmail.test'});
  assert.deepEqual(await verifyGoogleIdToken(jwt({aud: kGoogleIdTokenAudiences[1], iss: 'accounts.google.com'}), certs),
    {sub: 'g-123', email: 'player@gmail.test'});
});

test('a forged, foreign, expired or unverified token is refused', async () => {
  const refused = {
    'signed by another key': jwt({}, {key: attacker.privateKey}),
    'unknown key id': jwt({}, {kid: 'other'}),
    'unsigned (alg none)': jwt({}, {alg: 'none'}),
    'payload altered after signing': (() => {
      const [h, , s] = jwt().split('.');
      return `${h}.${b64({iss: 'https://accounts.google.com', aud: kGoogleIdTokenAudiences[0], sub: 'victim',
        email: 'victim@gmail.test', email_verified: true, iat: now(), exp: now() + 3000})}.${s}`;
    })(),
    'other application': jwt({aud: 'another-app.apps.googleusercontent.com'}),
    'other issuer': jwt({iss: 'https://evil.example'}),
    'expired': jwt({iat: now() - 7200, exp: now() - 3600}),
    'address not verified': jwt({email_verified: false}),
    'no address': jwt({email: undefined}),
    'no subject': jwt({sub: undefined}),
    'not a token': 'not-a-token',
  };
  for (const [name, token] of Object.entries(refused)) {
    assert.equal(await verifyGoogleIdToken(token, certs), null, name);
  }
});

test('the unsigned emulator token is accepted only by the isolated demo emulators', async () => {
  const unsigned = JSON.stringify({sub: 'g-emu', email: 'emu@gmail.test', email_verified: true});
  assert.deepEqual(await verifyGoogleIdToken(unsigned, certs), {sub: 'g-emu', email: 'emu@gmail.test'});
  assert.equal(await verifyGoogleIdToken(JSON.stringify({sub: 'g-emu', email: 'emu@gmail.test'}), certs), null);
  const saved = {host: process.env.FIREBASE_AUTH_EMULATOR_HOST, project: process.env.GCLOUD_PROJECT};
  try {
    delete process.env.FIREBASE_AUTH_EMULATOR_HOST; // As in production.
    assert.equal(await verifyGoogleIdToken(unsigned, certs), null);
    process.env.FIREBASE_AUTH_EMULATOR_HOST = saved.host;
    process.env.GCLOUD_PROJECT = 'proxi-play-odzp2e'; // Emulator host set on a real project.
    assert.equal(await verifyGoogleIdToken(unsigned, certs), null);
  } finally {
    process.env.FIREBASE_AUTH_EMULATOR_HOST = saved.host;
    process.env.GCLOUD_PROJECT = saved.project;
  }
});
