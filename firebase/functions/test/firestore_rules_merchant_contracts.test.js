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
