// Regression test for a real, confirmed-impact bug: both places that
// compute partner_delivery_eligible compared fulfillment.type === 'partner',
// but prizeFulfillment() returns a plain STRING ('merchant'|'partner'|
// 'platform'), never an object -- so 'partner'.type is undefined and the
// flag was ALWAYS false, for every partner prize, main or instant. Since
// queuePartnerPrize() (partner_prize_delivery.js:20) hard-requires
// partner_delivery_eligible===true before it will even look at a prize,
// this silently broke the entire partner email delivery pipeline in
// production (confirmed: it is the root cause of 5 pre-existing failures
// in admin_managed_delivery.test.js, reproduced identically before this
// fix). Introduced in 6a16eda (28/09) at both call sites:
//   - main_prize_draw.js (main prize draw)
//   - participate_in_game_transaction.js (instant win)
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-partner-delivery-eligible';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const { drawMainPrize } = require('../main_prize_draw');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

// ---------------------------------------------------------------------
// Main prize draw (drawMainPrize): merchant -> false, platform -> false,
// partner -> true.
// ---------------------------------------------------------------------
async function seedMainDraw(fulfillmentType) {
  const owned = fulfillmentType === 'merchant';
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('users/player').set({ user_role: 'joueur', first_name: 'Alice', city: 'Lille' });
  await db.doc('enseignes/shop').set({
    name: 'Club', email: 'shop@example.test',
    ...(owned ? { owner: db.doc('users/merchant'), owner_id: db.doc('users/merchant') } : { managed_by_admin: true }),
  });
  await db.doc('games/g').set({
    hasWinner: false, hasMainPrize: true, name: 'Lot',
    owner_id: owned ? db.doc('users/merchant') : null,
    fulfillment_type: fulfillmentType,
    ...(fulfillmentType === 'partner' ? { partner_delivery_enabled: true } : {}),
    enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
  });
  await db.doc('games/g/participants/t1').set({ user_id: db.doc('users/player') });
}

for (const [fulfillmentType, expected] of [['merchant', false], ['platform', false], ['partner', true]]) {
  test(`drawMainPrize: partner_delivery_eligible is ${expected} for fulfillment_type='${fulfillmentType}'`, async () => {
    await seedMainDraw(fulfillmentType);
    const result = await drawMainPrize('g', { now: admin.firestore.Timestamp.now() });
    assert.equal(result.status, 'completed');
    const prize = (await db.doc('prizes/' + result.prizeId).get()).data();
    assert.equal(prize.fulfillment_type, fulfillmentType);
    assert.equal(prize.partner_delivery_eligible, expected);
  });
}

// ---------------------------------------------------------------------
// Instant win (participate_in_game_transaction): same three cases,
// through the production callable, to cover the SECOND occurrence of the
// same bug independently of drawMainPrize().
// ---------------------------------------------------------------------
const playerSetup = async () => {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('users/player').set({ user_role: 'joueur', first_name: 'Bob', city: 'Metz', remaining_part: 3 });
};
async function seedInstantGame(fulfillmentType) {
  const owned = fulfillmentType === 'merchant';
  await db.doc('enseignes/shop').set({
    name: 'Club', email: 'shop@example.test',
    ...(owned ? { owner: db.doc('users/merchant'), owner_id: db.doc('users/merchant') } : { managed_by_admin: true }),
  });
  await db.doc('games/g').set({
    name: 'Lot', status: 'active', access_mode: 'public',
    create_by: db.doc('users/merchant'),
    owner_id: owned ? db.doc('users/merchant') : null,
    fulfillment_type: fulfillmentType,
    ...(fulfillmentType === 'partner' ? { partner_delivery_enabled: true } : {}),
    enseigne_id: db.doc('enseignes/shop'), participations: 0,
    start_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2030-01-01')),
  });
  await db.doc('games/g/instant_winners/instant').set({
    date: admin.firestore.Timestamp.now(), hasWinner: false,
    secondary_prize_name: 'Gain instantane', secondary_prize_presentation: 'Fixture',
  });
}

for (const [fulfillmentType, expected] of [['merchant', false], ['platform', false], ['partner', true]]) {
  test(`participateInGameTransaction (instant win): partner_delivery_eligible is ${expected} for fulfillment_type='${fulfillmentType}'`, async () => {
    await playerSetup();
    await seedInstantGame(fulfillmentType);
    const play = ft.wrap(require('../participate_in_game_transaction').participateInGameTransaction);
    const result = await play({ gameRef: 'g', from_qr: false }, { auth: { uid: 'player' } });
    assert.equal(result.isWin, true);
    const prize = (await db.doc(result.prize_id).get()).data();
    assert.equal(prize.fulfillment_type, fulfillmentType);
    assert.equal(prize.partner_delivery_eligible, expected);
  });
}
