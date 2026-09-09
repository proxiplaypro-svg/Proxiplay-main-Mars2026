process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-main-draw-audit';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const ft = require('firebase-functions-test')();
const draw = ft.wrap(require('../index').pickMainPrizeWinners);
const db = admin.firestore();
test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await db.doc('users/winner').set({user_role: 'joueur', first_name: 'Alice'});
  await db.doc('users/merchant').set({user_role: 'commercant'});
  await db.doc('enseignes/shop').set({owner: db.doc('users/merchant')});
  await db.doc('games/game').set({hasWinner: false, hasMainPrize: true, name: 'Lot',
    create_by: db.doc('users/merchant'), enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01'))});
});
test.after(() => ft.cleanup());
async function participant() { await db.doc('games/game/participants/one').set({user_id: db.doc('users/winner')}); }
test('main draw with no participant creates no phantom prize', async () => {
  await draw({}); assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('games/game').get()).data().hasWinner, false);
});
test('one participant, repeated and concurrent draws yield exactly one visible prize', async () => {
  await participant(); await Promise.all([draw({}), draw({})]); await draw({});
  const prizes = await db.collection('prizes').get(); assert.equal(prizes.size, 1);
  const prize = prizes.docs[0];
  assert.equal(prize.data().winner_id.path, 'users/winner');
  assert.equal((await db.doc(`users/winner/my_lots/${prize.id}`).get()).data().prize_id.path, prize.ref.path);
});
test('failure after queued writes rolls back game, prize and my_lots', async () => {
  await participant();
  const original = db.runTransaction;
  db.runTransaction = function (callback, options) {
    return original.call(this, async tx => { await callback(tx); throw new Error('injected before commit'); }, options);
  };
  try { await assert.rejects(draw({}), /draw\(s\) failed/); }
  finally { db.runTransaction = original; }
  assert.equal((await db.doc('games/game').get()).data().hasWinner, false);
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.collection('users/winner/my_lots').get()).size, 0);
});

for (const [label, data] of [['missing', null], ['suspended', {account_status:'suspended'}], ['deleted', {deleted:true}]]) {
  test(`main draw excludes ${label} accounts among valid tickets`, async () => {
    await participant();
    if (data) await db.doc('users/invalid').set(data);
    await db.doc('games/game/participants/invalid').set({user_id:db.doc('users/invalid')});
    await draw({});
    assert.equal((await db.collection('prizes').get()).docs[0].data().winner_id.path,'users/winner');
    assert.equal((await db.collection('users/invalid/my_lots').get()).size,0);
  });
}
test('all invalid participants finalize without prize and remain idempotent', async()=>{
  await db.doc('games/game/participants/invalid').set({user_id:db.doc('users/missing')});
  await draw({}); await draw({});
  assert.equal((await db.collection('prizes').get()).size,0);
  assert.equal((await db.doc('games/game').get()).data().draw_status,'no_eligible_entries');
});
