const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-proxiplay-ads',
    firestore: {host: '127.0.0.1', port: 8080,
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')},
  });
});
test.after(async () => env?.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('ads/open').set({
      enabled: true, image_url: 'https://x/open.png', destination_url: 'https://x',
      frequency_cap_hours: 24, impressions: 0, clicks: 0,
    });
    await db.doc('ads/home_banner').set({
      enabled: true, image_url: 'https://x/banner.png', destination_url: 'https://x',
      impressions: 0, clicks: 0,
    });
  });
});

test('anyone, signed in or not, can read an ad placement (shown to guests too)', async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(anon.doc('ads/open').get());
  await assertSucceeds(anon.doc('ads/home_banner').get());

  const player = env.authenticatedContext('player').firestore();
  await assertSucceeds(player.doc('ads/open').get());
});

test('a player can never write an ad placement, notably not the impression/click counters', async () => {
  const player = env.authenticatedContext('player').firestore();
  await assertFails(player.doc('ads/open').update({enabled: false}));
  await assertFails(player.doc('ads/open').update({impressions: 999999}));
  await assertFails(player.doc('ads/home_banner').update({clicks: 999999}));
  await assertFails(player.doc('ads/open').set({enabled: true, image_url: 'https://evil'}));
});

test('an unauthenticated client can never write an ad placement', async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(anon.doc('ads/open').update({enabled: false}));
});

test('admin can configure and update an ad placement', async () => {
  const admin = env.authenticatedContext('admin_uid', {admin: true}).firestore();
  await assertSucceeds(admin.doc('ads/open').update({
    enabled: false, destination_url: 'https://new-url.test',
  }));
  await assertSucceeds(admin.doc('ads/new_future_placement').set({enabled: false}));
});
