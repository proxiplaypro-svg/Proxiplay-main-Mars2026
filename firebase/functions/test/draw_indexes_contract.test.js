const test = require('node:test');
const assert = require('node:assert/strict');
const {indexes, fieldOverrides} = require('../../firestore.indexes.json');
test('range queries used by participation and scheduled draws have declared indexes', () => {
  for (const [collection, equality, range] of [
    ['instant_winners', 'hasWinner', 'date'], ['games', 'hasWinner', 'end_date'],
    ['animations', 'status', 'end_date'], ['referral_games', 'status', 'end_date'],
    ['referral_games', 'status', 'start_date'],
    ['referral_reward_pending','status','accepted_at'], ['referral_reward_pending','game_id','status'],
  ]) assert.ok(indexes.some(i => i.collectionGroup === collection && i.queryScope === 'COLLECTION' &&
    i.fields.length === 2 && i.fields[0].fieldPath === equality && i.fields[1].fieldPath === range &&
    i.fields.every(f => f.order === 'ASCENDING')), `${collection}: ${equality}, ${range}`);
});
test('filtered collection group queries have group scope indexes', () => {
  for (const [collection, field] of [['monthly_challenges', 'month'], ['favorite_enseignes', 'enseigne_id'], ['participants', 'user_id'], ['my_lots','prize_id']]) {
    assert.ok(fieldOverrides.some(i => i.collectionGroup === collection && i.fieldPath === field &&
      i.indexes.some(f => f.queryScope === 'COLLECTION_GROUP' && f.order === 'ASCENDING')), `${collection}.${field}`);
  }
});
