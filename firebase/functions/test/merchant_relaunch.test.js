// Merchant "no active game" relaunch: never email a merchant whose game is running.
// Isolated demo emulator only; e-mails are captured by a fake sender.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw new Error('An isolated demo Firestore emulator is required');
}
process.env.FUNCTIONS_EMULATOR = 'true';
require('firebase-functions-test')();
const exported = require('../index'); // initializes the admin app
const db = admin.firestore();
const {runMerchantRelaunch} = require('../merchant_relaunch');

const NOW = Date.parse('2026-10-20T09:00:00Z'); // 11:00 Paris, the scheduled time
const HOUR = 3600000, DAY = 24 * HOUR;
const at = ms => admin.firestore.Timestamp.fromMillis(ms);
const shopRef = id => db.doc(`enseignes/${id}`);

let sent, logs;
function deps(overrides = {}) {
  return {
    db, admin, now: NOW,
    logger: {log: m => logs.push(m), error: m => logs.push(m)},
    toDocRef: v => (v && typeof v.path === 'string' ? v : null),
    getTrimmedString: v => (typeof v === 'string' ? v.trim() : ''),
    pushCollection: 'ff_push_notifications',
    getOwnerContact: async () => ({email: 'owner@example.test', firstName: 'Camille', hasPushToken: false}),
    sendEmail: async (to, subject) => { sent.push({to, subject}); },
    ...overrides,
  };
}
// A shop created 10 days ago without newer game: due for the 7-day relaunch.
async function seedShop(id) {
  await shopRef(id).set({name: id, owner: db.doc('users/owner_' + id), created_time: at(NOW - 10 * DAY)});
}
async function seedGame(id, fields) {
  await db.doc(`games/${id}`).set({name: id, status: 'actif', visible_public: true,
    start_date: at(NOW - 5 * DAY), end_date: at(NOW + 5 * DAY), ...fields});
}
const sentTo = () => sent.length;

test.beforeEach(async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  await db.doc('app_config/notifications_auto').set({merchant_relaunch_enabled: true});
  sent = []; logs = [];
});

test('the production case: a running game flagged visible_public:false / brouillon blocks the relaunch', async () => {
  await seedShop('malle');
  // Same shape as the real game: stale draft flags, but played every day.
  await seedGame('croquettes', {enseigne_id: shopRef('malle'), merchantRef: shopRef('malle'),
    merchant_id: 'malle', merchantId: 'malle', status: 'brouillon', visible_public: false,
    start_date: at(Date.parse('2026-10-04T22:00:00Z')), end_date: at(Date.parse('2026-11-06T23:00:00Z'))});
  // The production query missed it.
  const legacy = await db.collection('games').where('enseigne_id', '==', shopRef('malle'))
    .where('end_date', '>', at(NOW)).where('visible_public', '==', true).limit(1).get();
  assert.equal(legacy.empty, true);
  const stats = await runMerchantRelaunch(deps());
  assert.equal(sentTo(), 0);
  assert.equal(stats.sent7d, 0);
  assert.equal((await shopRef('malle').get()).data().last_relaunch_notif_7d_at, undefined);
  assert.ok(logs.some(l => l.includes('enseigne=malle decision=skip reason=active_game game=croquettes')));
});

test('a merchant with an active game is not relaunched; one without is', async () => {
  await seedShop('active'); await seedGame('g1', {enseigne_id: shopRef('active')});
  await seedShop('idle'); await seedGame('old', {enseigne_id: shopRef('idle'), end_date: at(NOW - 3 * DAY)});
  const stats = await runMerchantRelaunch(deps());
  assert.deepEqual(sent.map(s => s.subject), ['[Camille], vos joueurs vous attendent sur ProxiPlay']);
  assert.equal(stats.sent7d, 1);
  assert.ok((await shopRef('idle').get()).data().last_relaunch_notif_7d_at);
  assert.equal((await shopRef('active').get()).data().last_relaunch_notif_7d_at, undefined);
});

test('a game starting later today and a game ending later today both block the relaunch', async () => {
  await seedShop('starts'); await seedGame('later', {enseigne_id: shopRef('starts'),
    start_date: at(NOW + 6 * HOUR), end_date: at(NOW + 10 * DAY)});
  await seedShop('ends'); await seedGame('tonight', {enseigne_id: shopRef('ends'), end_date: at(NOW + 10 * HOUR)});
  await seedShop('ended'); await seedGame('morning', {enseigne_id: shopRef('ended'), end_date: at(NOW - 2 * HOUR)});
  await runMerchantRelaunch(deps({getOwnerContact: async ref => ({email: ref.id + '@example.test', firstName: 'X'})}));
  assert.deepEqual(sent.map(s => s.to), ['owner_ended@example.test']);
});

test('draw games and instant-win games both count as active', async () => {
  await seedShop('draw'); await seedGame('draw_game', {enseigne_id: shopRef('draw'), hasMainPrize: true, game_type: 'scratcher'});
  await seedShop('instant'); await seedGame('instant_game', {enseigne_id: shopRef('instant'), hasMainPrize: false,
    game_type: 'scratcher', secondary_prizes: [{name: 'lot', count: 3}]});
  await runMerchantRelaunch(deps());
  assert.equal(sentTo(), 0);
});

test('games attached by another identifier still block the relaunch', async () => {
  const cases = {
    by_path: {enseigne_id: 'enseignes/by_path'},
    by_ref_field: {enseigne_ref: null},
    by_merchant_ref: {merchantRef: null},
    by_merchant_id: {merchant_id: 'by_merchant_id'},
    by_merchant_id_camel: {merchantId: 'by_merchant_id_camel'},
  };
  for (const [id, link] of Object.entries(cases)) {
    await seedShop(id);
    const fields = Object.fromEntries(Object.entries(link).map(([k, v]) => [k, v ?? shopRef(id)]));
    await seedGame('g_' + id, fields);
  }
  await runMerchantRelaunch(deps());
  assert.equal(sentTo(), 0);
});

test('a Firestore read error never sends a relaunch', async () => {
  await seedShop('unreadable');
  const failingDb = {
    collection: name => name === 'games'
      ? {where: () => ({get: async () => { throw new Error('UNAVAILABLE'); }})}
      : db.collection(name),
  };
  const stats = await runMerchantRelaunch(deps({db: failingDb}));
  assert.equal(sentTo(), 0);
  assert.equal(stats.errors, 1);
  assert.equal((await shopRef('unreadable').get()).data().last_relaunch_notif_7d_at, undefined);
  assert.ok(logs.some(l => l.includes('decision=skip reason=games_read_failed')));
});

test('uncertain or closed games: no end date blocks, a cancelled game does not', async () => {
  await seedShop('no_end'); await seedGame('legacy', {enseigne_id: shopRef('no_end'), end_date: null});
  await seedShop('cancelled'); await seedGame('stopped', {enseigne_id: shopRef('cancelled'), status: 'cancelled'});
  await runMerchantRelaunch(deps({getOwnerContact: async ref => ({email: ref.id + '@example.test', firstName: 'X'})}));
  assert.deepEqual(sent.map(s => s.to), ['owner_cancelled@example.test']);
});

test('legitimate relaunches keep their tiers, anti-duplicate and switch', async () => {
  await seedShop('recent');
  await shopRef('recent').update({created_time: at(NOW - 2 * DAY)});
  await seedShop('long'); await shopRef('long').update({created_time: at(NOW - 30 * DAY)});
  await seedShop('already'); await shopRef('already').update({last_relaunch_notif_7d_at: at(NOW - 2 * DAY)});
  await runMerchantRelaunch(deps({getOwnerContact: async ref => ({email: ref.id + '@example.test', firstName: 'X'})}));
  assert.deepEqual(sent.map(s => [s.to, s.subject.includes('abonnement')]), [['owner_long@example.test', true]]);
  sent = [];
  await db.doc('app_config/notifications_auto').set({merchant_relaunch_enabled: false});
  const stats = await runMerchantRelaunch(deps());
  assert.equal(stats.disabled, true);
  assert.equal(sentTo(), 0);
});

test('index.js exports the scheduled function at 11:00 Paris', () => {
  const fn = exported.relaunchInactiveMerchants;
  assert.equal(fn.__endpoint.scheduleTrigger.schedule, '0 11 * * *');
  assert.equal(fn.__endpoint.scheduleTrigger.timeZone, 'Europe/Paris');
});
