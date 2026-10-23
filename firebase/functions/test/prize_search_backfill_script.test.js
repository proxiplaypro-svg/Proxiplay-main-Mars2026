// Runs the production backfill script against the isolated emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('demo emulator required');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const {searchMerchantPrizeCodesCore} = require('../merchant_prizes');
const run = (...flags) => JSON.parse(execFileSync(process.execPath,
  [path.join(__dirname, '../scripts/backfill_prize_search_codes.js'), '--project', process.env.GCLOUD_PROJECT, ...flags],
  {env: process.env, encoding: 'utf8'}));

test('only codes a merchant can still be offered are migrated, after an explicit --apply', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const merchant = db.doc('users/legacy-merchant');
  await db.doc('prizes/old').set({owner_id: merchant, claim_code: 'old-777'});
  await db.doc('prizes/nocode').set({owner_id: merchant});
  // A claimed code is shown flagged as collected, so it is migrated; a
  // platform lot is never suggested, so it is not.
  await db.doc('prizes/claimed').set({owner_id: merchant, claim_code: 'OLD778', claimed: true});
  await db.doc('prizes/platform').set({owner_id: merchant, claim_code: 'OLD779', prize_type: 'animation'});
  assert.deepEqual((await searchMerchantPrizeCodesCore('legacy-merchant', 'OLD')).ids, []);
  assert.deepEqual(run(), {projectId: process.env.GCLOUD_PROJECT, apply: false, all: false, wonWithinDays: null,
    limit: null, owner: null, scanned: 4, pending: 2, written: 0, skippedNotSuggestible: 1, skippedOlder: 0});
  assert.equal((await db.doc('prizes/old').get()).data().claim_code_search, undefined);
  assert.equal(run('--apply').written, 2);
  assert.equal((await db.doc('prizes/old').get()).data().claim_code_search, 'OLD777');
  assert.equal((await db.doc('prizes/claimed').get()).data().claim_code_search, 'OLD778');
  assert.equal((await db.doc('prizes/platform').get()).data().claim_code_search, undefined);
  assert.deepEqual((await searchMerchantPrizeCodesCore('legacy-merchant', 'OLD')).ids, ['old', 'claimed']);
  assert.equal(run('--apply').written, 0);
  // A global migration needs its own explicit flag.
  assert.equal(run('--all').pending, 1);
});

test('--won-within-days limits the migration to recent wins', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const merchant = db.doc('users/legacy-merchant');
  const daysAgo = n => admin.firestore.Timestamp.fromMillis(Date.now() - n * 86400000);
  await db.doc('prizes/recent').set({owner_id: merchant, claim_code: 'NEW00001', win_date: daysAgo(10)});
  await db.doc('prizes/old').set({owner_id: merchant, claim_code: 'OLD00001', win_date: daysAgo(200)});
  const result = run('--won-within-days', '90');
  assert.equal(result.pending, 1);
  assert.equal(result.skippedOlder, 1);
  assert.equal(run('--won-within-days', '90', '--apply').written, 1);
  assert.equal((await db.doc('prizes/recent').get()).data().claim_code_search, 'NEW00001');
  assert.equal((await db.doc('prizes/old').get()).data().claim_code_search, undefined);
  // The old code is still found when typed in full.
  assert.deepEqual((await searchMerchantPrizeCodesCore('legacy-merchant', 'OLD00001')).ids, ['old']);
});

test('a controlled trial touches at most N prizes of the chosen merchant', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const alice = db.doc('users/alice'), bob = db.doc('users/bob');
  for (let i = 0; i < 4; i++) await db.doc('prizes/a' + i).set({owner_id: alice, claim_code: 'ALICE00' + i});
  await db.doc('prizes/b0').set({owner_id: bob, claim_code: 'BOB00000'});
  const trial = run('--owner', 'alice', '--limit', '2', '--apply');
  assert.equal(trial.written, 2);
  assert.equal(trial.updatedIds.length, 2);
  const migrated = (await db.collection('prizes').get()).docs.filter(d => d.data().claim_code_search).map(d => d.id);
  assert.deepEqual(migrated.sort(), [...trial.updatedIds].sort());
  assert.ok(migrated.every(id => id.startsWith('a')), 'only the chosen merchant');
});
