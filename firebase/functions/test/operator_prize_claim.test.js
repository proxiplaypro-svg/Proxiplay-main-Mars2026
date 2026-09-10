const {test, assert, db, ft, time, client, assertFails, assertSucceeds} = require('./lifecycle_helpers.cjs');
const claim = ft.wrap(require('../operator_prize_claim').claimOperatorPrize);
const input = {prizeId: 'p', winnerId: 'player', code: 'FIXTURE123', requestId: 'operator_fixture_retry'};
const call = (extra = {}, uid = 'operator') => claim({...input, ...extra}, {auth: {uid}});
test('new withdrawal attempt and legacy used status are refused; exact retry cannot change claimant', async () => {
  await fixture();
  await call();
  await assert.rejects(call({requestId: 'another_request_identifier'}), {code: 'already-exists'});
  await assert.rejects(call({requestId: undefined}), {code: 'already-exists'});
  await db.doc('users/second_admin').set({user_role: 'admin'});
  await assert.rejects(call({}, 'second_admin'), {code: 'already-exists'});
  for (const extra of [{claimed:true}, {status:'reclame'}, {claimed_at:time('2026-09-01')}]) {
    await fixture(extra);
    await assert.rejects(call(), {code: 'already-exists'});
  }
});
async function fixture(extra = {}) {
  await db.doc('prizes/p').set({winner_id: db.doc('users/player'), fulfillment_type: 'platform', claimed: false, claim_code: input.code, ...extra});
  await db.doc('users/player/my_lots/p').set({prize_id: db.doc('prizes/p')});
}
test('partner operator claim is atomic and retry preserves timestamps', async () => {
  await fixture({fulfillment_type: 'partner'});
  await assertSucceeds(client('player').doc('prizes/p').get());
  await assertSucceeds(client('player').doc('users/player/my_lots/p').get());
  await assertSucceeds(client('operator').doc('prizes/p').get());
  for (const uid of ['merchant', 'other']) {
    await assertFails(client(uid).doc('prizes/p').get());
    await assertFails(client(uid).doc('prizes/p').update({claimed: true}));
  }
  assert.deepEqual((await Promise.all([call(), call()])).map(r=>r.status).sort(), ['already_claimed','claimed']);
  const before = (await db.doc('prizes/p').get()).data(); process.env.LIFECYCLE_TEST_NOW = '2031-01-01';
  assert.equal((await call()).status, 'already_claimed'); assert.deepEqual((await db.doc('prizes/p').get()).data(), before);
});
test('operator claim refuses wrong role, winner, code and missing auth', async () => {
  await fixture();
  for (const uid of ['player','merchant','other']) await assert.rejects(call({},uid), {code:'permission-denied'});
  await assert.rejects(claim(input, {}), {code:'unauthenticated'});
  for (const extra of [{winnerId:'other'},{code:'wrong'},{prizeId:'missing'}]) await assert.rejects(call(extra), {code:'failed-precondition'});
  assert.equal((await db.doc('prizes/p').get()).data().claimed, false);
});
test('expired, malformed, merchant, ambiguous historical or previously claimed require review', async () => {
  for (const extra of [{usage_deadline:time('2020-01-01')},{usage_deadline:'bad'},{status:'expire'},{status:'expired'},{fulfillment_type:'merchant'},
    {fulfillment_type:null},{claimed:'false'}]) {
    await fixture(extra); await assert.rejects(call(), {code:'failed-precondition'});
  }
});
test('legacy platform without deadline/claimed works; missing link and suspended winner fail', async () => {
  await fixture(); await db.doc('users/player/my_lots/p').delete(); await assert.rejects(call(), {code:'failed-precondition'});
  await fixture(); await db.doc('users/player').update({account_status:'suspended'}); await assert.rejects(call(), {code:'failed-precondition'});
  await db.doc('users/player').update({account_status:'active'});
  await db.doc('prizes/p').update({claimed:require('firebase-admin').firestore.FieldValue.delete()});
  assert.equal((await call()).status,'claimed');
});
