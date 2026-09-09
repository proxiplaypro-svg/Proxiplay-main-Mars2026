const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-proxiplay-audit-security', firestore: {
    host: '127.0.0.1', port: 8080,
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('users/merchant').set({user_role: 'commercant', account_status: 'approved'});
    await db.doc('games/game').set({create_by: db.doc('users/merchant')});
    await db.doc('enseignes/shop').set({owner: db.doc('users/merchant')});
    for (const [id, fields] of Object.entries({
      expired: {usage_deadline: new Date('2020-01-01')},
      future: {usage_deadline: new Date('2099-01-01')}, legacy: {},
      used: {claimed: true}, inject: {},
    })) await db.doc(`prizes/${id}`).set({owner_id: db.doc('users/merchant'), claimed: false, ...fields});
  });
});
test.after(async () => { if (env) await env.cleanup(); });
test('self signup cannot inject the admin role alias', async () => {
  const db = env.authenticatedContext('attacker').firestore();
  await assertFails(db.doc('users/attacker').set({uid: 'attacker', user_role: 'joueur', userRole: 'admin'}));
});
test('merchant cannot add a missing winner or remove its ownership', async () => {
  const db = env.authenticatedContext('merchant').firestore();
  await assertFails(db.doc('games/game').update({hasWinner: true}));
  await assertFails(db.doc('games/game').set({hidden_from_merchant_stats: true}));
  await assertFails(db.doc('enseignes/shop').update({google_rating: 5}));
});
test('claim cannot carry an injected winner field', async () => {
  const db = env.authenticatedContext('merchant').firestore();
  await assertFails(db.doc('prizes/inject').update({claimed: true, winner_id: db.doc('users/merchant')}));
});
test('expired and used prizes cannot be claimed; future and undated prizes can', async () => {
  const db = env.authenticatedContext('merchant').firestore();
  await assertFails(db.doc('prizes/expired').update({claimed: true}));
  await assertFails(db.doc('prizes/used').update({claimed: true}));
  await assertSucceeds(db.doc('prizes/future').update({claimed: true}));
  await assertSucceeds(db.doc('prizes/legacy').update({claimed: true}));
});
