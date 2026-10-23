// Storage rules for ad creatives: no client can list the ad folder or read
// an adults-only creative directly. Isolated demo Storage emulator only.
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {ref, uploadString, getBytes, listAll} = require('firebase/storage');

const [host, port] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199').split(':');
let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-proxiplay-storage-ads',
    storage: {host, port: Number(port), rules: fs.readFileSync(path.resolve(__dirname, '../../storage.rules'), 'utf8')},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const storage = ctx.storage();
    await uploadString(ref(storage, 'ads/home_banner/1.png'), 'ordinary');
    await uploadString(ref(storage, 'ads_restricted/open/2.png'), 'adults-only');
  });
});
test.after(async () => env?.cleanup());

const clients = () => [
  ['invité', env.unauthenticatedContext().storage()],
  ['joueur', env.authenticatedContext('player', {email: 'player@example.test'}).storage()],
];

test('nobody but an admin can list the ad folders', async () => {
  for (const [, storage] of clients()) {
    await assertFails(listAll(ref(storage, 'ads')));
    await assertFails(listAll(ref(storage, 'ads/home_banner')));
    await assertFails(listAll(ref(storage, 'ads_restricted')));
  }
  const admin = env.authenticatedContext('admin', {email: 'proxiplay.pro@gmail.com'}).storage();
  await assertSucceeds(listAll(ref(admin, 'ads/home_banner')));
});

test('an adults-only creative cannot be read directly, an ordinary one can', async () => {
  for (const [, storage] of clients()) {
    await assertFails(getBytes(ref(storage, 'ads_restricted/open/2.png')));
    await assertSucceeds(getBytes(ref(storage, 'ads/home_banner/1.png')));
  }
  const admin = env.authenticatedContext('admin', {email: 'proxiplay.pro@gmail.com'}).storage();
  await assertSucceeds(getBytes(ref(admin, 'ads_restricted/open/2.png')));
});

test('no client can upload or replace a creative', async () => {
  for (const [, storage] of clients()) {
    await assertFails(uploadString(ref(storage, 'ads/home_banner/forged.png'), 'x'));
    await assertFails(uploadString(ref(storage, 'ads_restricted/open/forged.png'), 'x'));
  }
});
