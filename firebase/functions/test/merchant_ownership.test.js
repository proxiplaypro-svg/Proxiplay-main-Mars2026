const {test} = require('node:test');
const assert = require('node:assert/strict');
const {shopOwnerPath, ownsPrize, gamePrizeOwnership} = require('../merchant_ownership');
const {auditOwners} = require('../scripts/audit_owner_compatibility');
const fakeDb = {doc: (path) => ({path})};
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
// FAILLE 2, cause structurelle : owner_id doit identifier le RESPONSABLE DE
// LA REMISE, jamais seulement l'enseigne hote. Avant ce correctif, un lot
// 'platform' heritait de owner_id == marchand des que l'enseigne avait un
// proprietaire -- 'partner' etait deja protege par ailleurs (prizeFulfillment
// interdit cette valeur avec un proprietaire), mais rien ne protegeait
// 'platform' au niveau de gamePrizeOwnership() lui-meme.
test('gamePrizeOwnership: owner_id marchand uniquement pour fulfillment_type merchant', () => {
  const ownership = {valid: true, ownerPath: 'users/merchant'};
  const shopRef = {path: 'enseignes/shop'};

  const merchantPrize = gamePrizeOwnership(fakeDb, ownership, shopRef, 'merchant');
  assert.equal(merchantPrize.owner_id.path, 'users/merchant');
  assert.equal(merchantPrize.fulfillment_type, 'merchant');
  assert.equal('partner_ref' in merchantPrize, false);

  const partnerPrize = gamePrizeOwnership(fakeDb, ownership, shopRef, 'partner');
  assert.equal(partnerPrize.owner_id, null);
  assert.equal(partnerPrize.fulfillment_type, 'partner');
  assert.equal(partnerPrize.partner_ref, shopRef);

  const platformPrize = gamePrizeOwnership(fakeDb, ownership, shopRef, 'platform');
  assert.equal(platformPrize.owner_id, null);
  assert.equal(platformPrize.fulfillment_type, 'platform');
  assert.equal('partner_ref' in platformPrize, false);
});

test('gamePrizeOwnership: boutique sans proprietaire (geree admin) ne force jamais owner_id, quel que soit fulfillment_type', () => {
  const ownerless = {valid: true, ownerPath: ''};
  for (const fulfillmentType of ['merchant', 'partner', 'platform']) {
    assert.equal(gamePrizeOwnership(fakeDb, ownerless, {path: 'enseignes/shop'}, fulfillmentType).owner_id, null);
  }
});

test('offline audit proposes normalization only for compatible histories', () => {
  assert.deepEqual(auditOwners([
    {id: 'legacy', owner: '/users/merchant'},
    {id: 'modern', owner: {path: 'users/merchant'}, owner_id: {path: 'users/merchant'}},
    {id: 'conflict', owner: 'merchant', owner_id: 'other'},
  ]).map(r => r.status), ['compatible_normalization', 'canonical', 'manual_review']);
});
