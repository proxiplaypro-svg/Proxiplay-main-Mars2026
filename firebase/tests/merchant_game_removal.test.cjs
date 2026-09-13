const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const localRequire = createRequire(path.resolve(__dirname, '../functions/package.json'));
const {initializeTestEnvironment, assertFails, assertSucceeds} = localRequire('@firebase/rules-unit-testing');
let env;
test.before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Local emulator required');
  env = await initializeTestEnvironment({
    projectId: 'demo-proxiplay-removal',
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8')},
  });
});
test.after(async () => { if (env) await env.cleanup(); });
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await db.doc('users/merchant').set({user_role: 'commercant', account_status: 'approved'});
    await db.doc('enseignes/shop').set({owner_id: db.doc('users/merchant')});
    for (const [id, dates] of Object.entries({
      ended: {start_date: new Date('2000-01-01'), end_date: new Date('2001-01-01')},
      active: {start_date: new Date('2000-01-01'), end_date: new Date('2099-01-01')},
      future: {start_date: new Date('2098-01-01'), end_date: new Date('2099-01-01')},
      undated: {}, invalid: {end_date: '2001-01-01'},
    })) await db.doc(`games/${id}`).set({
      owner_id: db.doc('users/merchant'), enseigne_id: db.doc('enseignes/shop'),
      hidden_from_merchant_stats: false, ...dates,
    });
  });
});
function hide(db, id, extra = {}) {
  return db.doc(`games/${id}`).update({hidden_from_merchant_stats: true, updated_time: new Date(), ...extra});
}
test('owner may remove an ended game', async () => {
  await assertSucceeds(hide(env.authenticatedContext('merchant').firestore(), 'ended'));
});
for (const id of ['active', 'future', 'undated', 'invalid']) {
  test(`owner cannot remove ${id} game`, async () => {
    await assertFails(hide(env.authenticatedContext('merchant').firestore(), id));
  });
}
test('non owner cannot remove an ended game', async () => {
  await assertFails(hide(env.authenticatedContext('other').firestore(), 'ended'));
});
test('owner cannot bypass by changing the end date', async () => {
  await assertFails(hide(env.authenticatedContext('merchant').firestore(), 'active', {end_date: new Date('2001-01-01')}));
});
test('admin keeps existing access to active future and undated games', async () => {
  const db = env.authenticatedContext('admin', {admin: true}).firestore();
  for (const id of ['active', 'future', 'undated']) await assertSucceeds(hide(db, id));
});
test('unrelated allowed merchant metadata update is unchanged', async () => {
  await assertSucceeds(env.authenticatedContext('merchant').firestore().doc('games/active').update({updated_time: new Date()}));
});
