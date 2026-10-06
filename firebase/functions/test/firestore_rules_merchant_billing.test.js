const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-proxiplay-merchant-billing',
    firestore: {host: '127.0.0.1', port: 8080,
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')},
  });
});
test.after(async () => env?.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('enseignes/shop').set({owner: '/users/merchant', owner_id: db.doc('users/merchant')});
    await db.doc('enseignes/other_shop').set({owner_id: db.doc('users/other_merchant')});
    await db.doc('merchant_subscriptions/shop').set({
      enseigne_id: db.doc('enseignes/shop'),
      merchant_user_id: db.doc('users/merchant'),
      subscription_status: 'incomplete',
    });
    await db.doc('merchant_referrals/shop').set({
      enseigne_id: db.doc('enseignes/shop'),
      merchant_user_id: db.doc('users/merchant'),
      inviter_user_id: db.doc('users/player_inviter'),
      status: 'linked',
    });
    await db.doc('merchant_referral_codes/ABCD1234').set({inviter_user_id: db.doc('users/player_inviter')});
    await db.doc('stripe_webhook_events/evt_1').set({type: 'invoice.paid', status: 'done'});
  });
});

test('merchant can read own subscription, never another merchant\'s, and can never write it', async () => {
  const merchant = env.authenticatedContext('merchant').firestore();
  await assertSucceeds(merchant.doc('merchant_subscriptions/shop').get());
  await assertFails(merchant.doc('merchant_subscriptions/shop').update({subscription_status: 'active'}));
  await assertFails(merchant.doc('merchant_subscriptions/shop').set({subscription_status: 'active'}));

  const other = env.authenticatedContext('other_merchant').firestore();
  await assertFails(other.doc('merchant_subscriptions/shop').get());
});

test('a player cannot self-assign a subscription by writing a fresh merchant_subscriptions document', async () => {
  const attacker = env.authenticatedContext('attacker').firestore();
  await assertFails(attacker.doc('merchant_subscriptions/shop').set({subscription_status: 'active'}));
});

test('merchant owner and inviter can read a merchant_referral, a third party cannot, nobody can write', async () => {
  const merchant = env.authenticatedContext('merchant').firestore();
  await assertSucceeds(merchant.doc('merchant_referrals/shop').get());
  const inviter = env.authenticatedContext('player_inviter').firestore();
  await assertSucceeds(inviter.doc('merchant_referrals/shop').get());
  const stranger = env.authenticatedContext('stranger').firestore();
  await assertFails(stranger.doc('merchant_referrals/shop').get());

  await assertFails(merchant.doc('merchant_referrals/shop').update({status: 'paid'}));
  await assertFails(inviter.doc('merchant_referrals/shop').update({status: 'approved'}));
});

test('a referral reward can never be self-approved/self-paid/self-rejected by any client', async () => {
  const attacker = env.authenticatedContext('attacker').firestore();
  await assertFails(attacker.doc('merchant_referrals/shop').update({
    status: 'paid', paid_reference: 'fake',
  }));
});

test('merchant_referral_codes: the owning inviter can read their own code, nobody can write directly', async () => {
  const inviter = env.authenticatedContext('player_inviter').firestore();
  await assertSucceeds(inviter.doc('merchant_referral_codes/ABCD1234').get());
  const stranger = env.authenticatedContext('stranger').firestore();
  await assertFails(stranger.doc('merchant_referral_codes/ABCD1234').get());
  await assertFails(stranger.doc('merchant_referral_codes/ZZZZ9999').set({inviter_user_id: 'users/stranger'}));
  await assertFails(inviter.doc('merchant_referral_codes/ABCD1234').update({inviter_user_id: 'users/stranger'}));
});

test('stripe_webhook_events is never readable nor writable by any client, admin included', async () => {
  const admin = env.authenticatedContext('admin_uid', {admin: true}).firestore();
  await assertFails(admin.doc('stripe_webhook_events/evt_1').get());
  await assertFails(admin.doc('stripe_webhook_events/evt_2').set({type: 'fake'}));
});

test('admin can read subscriptions and referrals across all merchants', async () => {
  const admin = env.authenticatedContext('admin_uid', {admin: true}).firestore();
  await assertSucceeds(admin.doc('merchant_subscriptions/shop').get());
  await assertSucceeds(admin.doc('merchant_referrals/shop').get());
  await assertSucceeds(admin.doc('merchant_referral_codes/ABCD1234').get());
});
