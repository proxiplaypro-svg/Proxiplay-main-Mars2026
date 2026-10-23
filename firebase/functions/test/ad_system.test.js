// recordAdEvent / getRestrictedAdCreative. Isolated demo emulator only.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-ad-system';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {recordAdEventHandler: record, getRestrictedAdCreativeHandler: creative, kExposureWindowMs} =
  require('../ad_system');

const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const hour = 3600000;
const guest = (ip, ua = 'Android') => ({rawRequest: {ip, headers: {'user-agent': ua}}});
const user = (uid) => ({auth: {uid}});
const adult = new Date(Date.now() - 30 * 365 * 24 * hour);
const minor = new Date(Date.now() - 15 * 365 * 24 * hour);

async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
}
// A live published campaign, as projected by the Admin.
async function live(placement = 'home_banner', campaign = 'c1', extra = {}) {
  await db.doc(`ads/${placement}`).set({campaign_id: campaign, enabled: true,
    image_url: 'https://x/ad.png', destination_url: 'https://x', start_at: ts(Date.now() - hour),
    end_at: ts(Date.now() + hour), impressions: 0, clicks: 0, ...extra});
  await db.doc(`ad_campaigns/${campaign}`).set({placement, impressions: 0, clicks: 0}, {merge: true});
}
const counters = async (placement = 'home_banner', campaign = 'c1') => ({
  placement: (await db.doc(`ads/${placement}`).get()).data(),
  campaign: (await db.doc(`ad_campaigns/${campaign}`).get()).data(),
});
const impression = (ctx, campaign = 'c1', placement = 'home_banner') =>
  record({placement, type: 'impression', campaign_id: campaign}, ctx);
const click = (ctx, campaign = 'c1', placement = 'home_banner') =>
  record({placement, type: 'click', campaign_id: campaign}, ctx);

test.beforeEach(reset);

test('rejects unknown placements, types and malformed campaigns', async () => {
  for (const input of [{placement: 'nope', type: 'impression'}, {placement: 'open', type: 'nope'},
    {placement: '../ad_campaigns/x', type: 'impression'},
    {placement: 'open', type: 'impression', campaign_id: '../x'}]) {
    await assert.rejects(record(input, guest('10.0.0.1')), {code: 'invalid-argument'});
  }
});

test('a real exposure is counted once on the placement and its campaign, guests included', async () => {
  await live();
  assert.equal((await impression(guest('10.0.0.1'))).status, 'recorded');
  assert.equal((await impression(user('player'))).status, 'recorded');
  const {placement, campaign} = await counters();
  assert.equal(placement.impressions, 2);
  assert.equal(campaign.impressions, 2);
});

test('refreshes and revisits within the window are not counted again', async () => {
  await live();
  await impression(user('player'));
  for (let i = 0; i < 3; i++) assert.equal((await impression(user('player'))).reason, 'duplicate_impression');
  await Promise.all([1, 2, 3].map(() => impression(guest('10.0.0.2'))));
  assert.equal((await counters()).placement.impressions, 2);
  // Another placement or campaign is another exposure.
  await live('open', 'c2');
  assert.equal((await impression(user('player'), 'c2', 'open')).status, 'recorded');
});

test('a new exposure after the window is counted again', async () => {
  await live();
  await impression(user('player'));
  const ref = (await db.collection('_ad_exposures').get()).docs[0].ref;
  await ref.update({last_impression_at: ts(Date.now() - kExposureWindowMs - 1000)});
  assert.equal((await impression(user('player'))).status, 'recorded');
  assert.equal((await counters()).placement.impressions, 2);
});

test('a click counts only after an impression, once per impression', async () => {
  await live();
  assert.equal((await click(user('player'))).reason, 'click_without_impression');
  await impression(user('player'));
  assert.equal((await click(user('player'))).status, 'recorded');
  assert.equal((await click(user('player'))).reason, 'duplicate_click');
  const {placement, campaign} = await counters();
  assert.equal(placement.clicks, 1);
  assert.equal(campaign.clicks, 1);
});

test('only the campaign currently published and running is credited', async () => {
  await live();
  await db.doc('ad_campaigns/other').set({impressions: 0});
  assert.equal((await impression(user('a'), 'other')).reason, 'stale_campaign');
  assert.equal((await impression(user('b'), '')).reason, 'stale_campaign');
  assert.equal((await db.doc('ad_campaigns/other').get()).data().impressions, 0);
  await db.doc('ads/home_banner').update({enabled: false});
  assert.equal((await impression(user('c'))).reason, 'inactive');
  await db.doc('ads/home_banner').update({enabled: true, end_at: ts(Date.now() - 1000)});
  assert.equal((await impression(user('d'))).reason, 'inactive');
  assert.equal((await impression(user('e'), 'c1', 'home_banner_referral')).reason, 'inactive');
  assert.equal((await counters()).placement.impressions, 0);
});

test('a flood from one source is rate limited without blocking others', async () => {
  await live();
  const ctx = guest('10.9.9.9');
  let limited = 0;
  for (let i = 0; i < 65; i++) {
    try { await impression(ctx); } catch (error) { assert.equal(error.code, 'resource-exhausted'); limited++; }
  }
  assert.ok(limited >= 5);
  assert.equal((await impression(guest('10.9.9.10'))).status, 'recorded');
});

test('nothing personal is stored: only salted fingerprints with an expiry', async () => {
  await live();
  await impression(guest('10.1.2.3', 'Mozilla/5.0 Samsung'));
  await impression(user('player-uid'));
  for (const name of ['_ad_exposures', '_ad_event_rate']) {
    for (const doc of (await db.collection(name).get()).docs) {
      const raw = JSON.stringify({id: doc.id, ...doc.data()});
      for (const secret of ['10.1.2.3', 'Samsung', 'player-uid']) assert.ok(!raw.includes(secret), `${name} leaks ${secret}`);
      assert.ok(doc.data().expires_at, `${name} has an expiry`);
    }
  }
});

test('an adults-only campaign is never counted for a minor, a guest or an unknown age', async () => {
  await live('open', 'adult', {adults_only: true});
  await db.doc('users/adult').set({birthday: adult});
  await db.doc('users/minor').set({birthday: minor});
  await db.doc('users/unknown').set({});
  for (const ctx of [user('minor'), user('unknown'), guest('10.0.0.5')]) {
    assert.equal((await impression(ctx, 'adult', 'open')).reason, 'adults_only');
  }
  assert.equal((await impression(user('adult'), 'adult', 'open')).status, 'recorded');
  assert.equal((await counters('open', 'adult')).campaign.impressions, 1);
});

test('the creative of an adults-only campaign is handed to signed-in adults only', async () => {
  // As projected by the Admin: no creative in the public document.
  await live('open', 'adult', {adults_only: true});
  await db.doc('ads/open').update({image_url: admin.firestore.FieldValue.delete(),
    destination_url: admin.firestore.FieldValue.delete()});
  await db.doc('ads_restricted/open').set({campaign_id: 'adult', image_url: 'https://x/adult.png',
    destination_url: 'https://x/shop'});
  await db.doc('users/adult').set({birthday: adult});
  await db.doc('users/minor').set({birthday: minor});
  await db.doc('users/unknown').set({});
  for (const ctx of [user('minor'), user('unknown'), user('ghost'), {}]) {
    assert.deepEqual(await creative({placement: 'open'}, ctx), {available: false});
  }
  assert.deepEqual(await creative({placement: 'open'}, user('adult')),
    {available: true, campaign_id: 'adult', image_url: 'https://x/adult.png', destination_url: 'https://x/shop'});
  // A stale restricted creative (another campaign) or an ordinary campaign gives nothing.
  await db.doc('ads_restricted/open').update({campaign_id: 'old'});
  assert.deepEqual(await creative({placement: 'open'}, user('adult')), {available: false});
  await live('home_banner', 'plain');
  assert.deepEqual(await creative({placement: 'home_banner'}, user('adult')), {available: false});
  await assert.rejects(creative({placement: 'nope'}, user('adult')), {code: 'invalid-argument'});
});
