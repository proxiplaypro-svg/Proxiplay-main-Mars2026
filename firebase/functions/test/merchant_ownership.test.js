const {test} = require('node:test');
const assert = require('node:assert/strict');
const {shopOwnerPath, ownsPrize} = require('../merchant_ownership');
const {auditOwners} = require('../scripts/audit_owner_compatibility');
test('owner legacy forms and canonical references normalize to the same trusted user', () => {
  for (const owner of ['merchant', 'users/merchant', '/users/merchant', {path: 'users/merchant'}]) {
    assert.equal(shopOwnerPath({owner}), 'users/merchant');
    assert.equal(shopOwnerPath({owner, owner_id: {path: 'users/merchant'}}), 'users/merchant');
  }
});
test('conflicting or malformed owners never authorize a fallback', () => {
  for (const row of [{}, {owner: '/shops/merchant'}, {owner: ''}, {owner: '/'},
    {owner: 'merchant', owner_id: 'other'}, {owner: {}, owner_id: 'merchant'}]) {
    assert.equal(shopOwnerPath(row), '');
  }
  assert.equal(ownsPrize({owner_id: 'other', enseigne_id: {path: 'enseignes/shop'}},
    'merchant', new Set(['enseignes/shop'])), false);
});
test('offline audit proposes normalization only for compatible histories', () => {
  assert.deepEqual(auditOwners([
    {id: 'legacy', owner: '/users/merchant'},
    {id: 'modern', owner: {path: 'users/merchant'}, owner_id: {path: 'users/merchant'}},
    {id: 'conflict', owner: 'merchant', owner_id: 'other'},
  ]).map(r => r.status), ['compatible_normalization', 'canonical', 'manual_review']);
});
