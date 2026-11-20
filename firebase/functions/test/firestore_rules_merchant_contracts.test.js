// Phase 1, tranche 1, lot 1.0 : regles Firestore des demandes de souscription.
// Le commercant ne lit que SES contrats (vue filtree), jamais les donnees
// internes ; aucun client (commercant, tiers, admin cote client) n'ecrit.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');

let env;
test.before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || 'demo-proxiplay-merchant-contracts',
    firestore: {host, port: Number(port),
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')},
  });
});
test.after(async () => env?.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('users/merchant').set({user_role: 'commercant', account_status: 'approved'});
    await db.doc('users/other').set({user_role: 'commercant', account_status: 'approved'});
    await db.doc('merchant_contracts/c1').set({owner_uid: 'merchant', state: 'submitted', enseigne_id: 'e1'});
    await db.doc('merchant_contracts/c1/internal/record').set({
      verification: {checks: {fraud: {result: 'manual', note: 'note interne'}}},
      refusal_reason: 'interne', acceptance: {ip: '203.0.113.9'},
    });
    await db.doc('merchant_contracts/c1/events/ev1').set({type: 'submitted'});
    await db.doc('merchant_contracts/c2').set({owner_uid: 'other', state: 'confirmed'});
    await db.doc('sales_reps/rep1').set({name: 'Commercial', active: true});
    await db.doc('rep_links/abc').set({rep_id: 'rep1'});
    await db.doc('promo_codes/BIENVENUE').set({kind: 'amount', value_cents: 5000, active: true});
    await db.doc('app_config/merchant_contracts').set({enabled: false});
    await db.doc('merchant_contracts_config_log/l1').set({by: 'admin', changes: {enabled: true}});
    await db.doc('payment_tokens/h1').set({contract_id: 'c1', owner_uid: 'merchant'});
    await db.doc('mail_outbox/o1').set({contract_id: 'c1', status: 'pending'});
    await db.doc('admin_alerts/a1').set({kind: 'email_echec', resolved: false});
  });
});

const merchant = () => env.authenticatedContext('merchant').firestore();
const other = () => env.authenticatedContext('other').firestore();
const adminClient = () => env.authenticatedContext('admin', {admin: true}).firestore();

test('le commercant lit son propre contrat, jamais celui d\'un autre', async () => {
  await assertSucceeds(merchant().doc('merchant_contracts/c1').get());
  await assertFails(merchant().doc('merchant_contracts/c2').get());
  await assertFails(other().doc('merchant_contracts/c1').get());
  await assertFails(env.unauthenticatedContext().firestore().doc('merchant_contracts/c1').get());
});

test('liste : seulement filtree sur son propre owner_uid', async () => {
  const db = merchant();
  const own = await assertSucceeds(db.collection('merchant_contracts').where('owner_uid', '==', 'merchant').get());
  assert.deepEqual(own.docs.map((d) => d.id), ['c1']);
  await assertFails(db.collection('merchant_contracts').get());
  await assertFails(db.collection('merchant_contracts').where('owner_uid', '==', 'other').get());
  await assertFails(db.collection('merchant_contracts').where('state', '==', 'submitted').get());
});

test('donnees internes (verification, notes, motif interne, IP) et journal : jamais lisibles par le commercant', async () => {
  const db = merchant();
  await assertFails(db.doc('merchant_contracts/c1/internal/record').get());
  await assertFails(db.collection('merchant_contracts/c1/internal').get());
  await assertFails(db.doc('merchant_contracts/c1/events/ev1').get());
  await assertFails(db.collection('merchant_contracts/c1/events').get());
  await assertFails(db.collectionGroup('internal').get());
  await assertFails(db.collectionGroup('events').get());
});

test('aucun client n\'ecrit : ni le proprietaire, ni un tiers, ni un admin cote client', async () => {
  for (const db of [merchant(), other(), adminClient(), env.unauthenticatedContext().firestore()]) {
    await assertFails(db.doc('merchant_contracts/c1').update({state: 'confirmed'}));
    await assertFails(db.doc('merchant_contracts/c1').set({owner_uid: 'merchant', state: 'confirmed'}));
    await assertFails(db.doc('merchant_contracts/c1').delete());
    await assertFails(db.doc('merchant_contracts/new').set({owner_uid: 'merchant', state: 'submitted'}));
    await assertFails(db.doc('merchant_contracts/c1/internal/record').set({verification: {}}));
    await assertFails(db.doc('merchant_contracts/c1/events/ev2').set({type: 'confirmed'}));
    await assertFails(db.doc('sales_reps/rep2').set({name: 'x'}));
    await assertFails(db.doc('rep_links/def').set({rep_id: 'rep1'}));
    await assertFails(db.doc('promo_codes/GRATUIT').set({kind: 'percent', value: 100}));
    await assertFails(db.doc('app_config/merchant_contracts').set({enabled: true}));
    await assertFails(db.doc('merchant_contracts_config_log/l2').set({by: 'x'}));
    await assertFails(db.doc('merchant_contracts_config_log/l1').delete());
  }
});

test('commerciaux, liens, codes et interrupteur : admin seul en lecture', async () => {
  for (const docPath of ['sales_reps/rep1', 'rep_links/abc', 'promo_codes/BIENVENUE', 'app_config/merchant_contracts',
    'merchant_contracts_config_log/l1']) {
    await assertFails(merchant().doc(docPath).get());
    await assertSucceeds(adminClient().doc(docPath).get());
  }
});

test('l\'admin lit tout le dossier (contrat, donnees internes, journal)', async () => {
  const db = adminClient();
  await assertSucceeds(db.doc('merchant_contracts/c2').get());
  await assertSucceeds(db.doc('merchant_contracts/c1/internal/record').get());
  await assertSucceeds(db.collection('merchant_contracts/c1/events').get());
  await assertSucceeds(db.collection('merchant_contracts').where('state', '==', 'submitted').get());
});

// Relecture des regles : app_config/merchant_contracts n'est couvert que par
// son propre match (ni match /app_config/{doc}, ni joker, ni attrape-tout).
// Aucun utilisateur non admin ne le lit, connecte ou non.
test('app_config/merchant_contracts : illisible pour un anonyme et pour tout utilisateur connecte non admin', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc('users/player').set({user_role: 'joueur'});
    await ctx.firestore().doc('users/fake_admin_field').set({user_role: 'commercant', admin: true});
  });
  const readers = [
    ['anonyme', env.unauthenticatedContext().firestore()],
    ['connecte sans profil', env.authenticatedContext('nobody').firestore()],
    ['joueur', env.authenticatedContext('player').firestore()],
    ['commercant valide', env.authenticatedContext('merchant').firestore()],
    ['claim admin a false', env.authenticatedContext('merchant', {admin: false}).firestore()],
    ['e-mail admin historique non verifie', env.authenticatedContext('x', {email: 'proxiplay.pro@gmail.com', email_verified: false}).firestore()],
    ['champ admin pose dans son propre profil', env.authenticatedContext('fake_admin_field').firestore()],
  ];
  for (const [label, db] of readers) {
    await assertFails(db.doc('app_config/merchant_contracts').get(), label);
    await assertFails(db.collection('app_config').where('enabled', '==', true).get(), label);
    await assertFails(db.collection('merchant_contracts_config_log').get(), label);
  }
  await assertSucceeds(adminClient().doc('app_config/merchant_contracts').get());
});

// Tranche 2a, lot 1.6
test('jetons de paiement : illisibles pour tous, admin compris ; file de reprise et alertes : admin seul ; aucune ecriture client', async () => {
  for (const db of [merchant(), other(), adminClient(), env.unauthenticatedContext().firestore()]) {
    await assertFails(db.doc('payment_tokens/h1').get());
    await assertFails(db.collection('payment_tokens').where('owner_uid', '==', 'merchant').get());
    await assertFails(db.doc('payment_tokens/h2').set({contract_id: 'c1'}));
    await assertFails(db.doc('mail_outbox/o2').set({status: 'pending'}));
    await assertFails(db.doc('admin_alerts/a2').set({kind: 'x'}));
    await assertFails(db.doc('admin_alerts/a1').update({resolved: true}));
  }
  for (const path of ['mail_outbox/o1', 'admin_alerts/a1']) {
    await assertFails(merchant().doc(path).get());
    await assertSucceeds(adminClient().doc(path).get());
  }
});

test('evenements Stripe non rattaches : admin seul en lecture, aucune ecriture client', async () => {
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('stripe_unmatched_events/evt_1').set({event_type: 'invoice.paid'}));
  for (const db of [merchant(), other(), adminClient(), env.unauthenticatedContext().firestore()]) {
    await assertFails(db.doc('stripe_unmatched_events/evt_2').set({event_type: 'x'}));
    await assertFails(db.doc('stripe_unmatched_events/evt_1').update({resolved: true}));
  }
  await assertFails(merchant().doc('stripe_unmatched_events/evt_1').get());
  await assertFails(env.unauthenticatedContext().firestore().doc('stripe_unmatched_events/evt_1').get());
  await assertSucceeds(adminClient().doc('stripe_unmatched_events/evt_1').get());
});

// Tranche 2a, lot 1.7
test('miroir enseigne_subscriptions : lu par le titulaire et l\'admin, jamais ecrit par un client', async () => {
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('enseigne_subscriptions/e1')
    .set({owner_uid: 'merchant', stripe_customer_id: 'cus_1', status: 'active'}));
  await assertSucceeds(merchant().doc('enseigne_subscriptions/e1').get());
  await assertSucceeds(merchant().collection('enseigne_subscriptions').where('owner_uid', '==', 'merchant').get());
  await assertFails(other().doc('enseigne_subscriptions/e1').get());
  await assertFails(env.unauthenticatedContext().firestore().doc('enseigne_subscriptions/e1').get());
  await assertSucceeds(adminClient().doc('enseigne_subscriptions/e1').get());
  for (const db of [merchant(), other(), adminClient()]) {
    await assertFails(db.doc('enseigne_subscriptions/e1').update({status: 'active'}));
    await assertFails(db.doc('enseigne_subscriptions/e9').set({owner_uid: 'merchant', status: 'active'}));
  }
});
