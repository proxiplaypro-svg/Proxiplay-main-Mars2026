const {gameOwnership} = require('./merchant_ownership');
const emailValid = value => typeof value === 'string' && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value.trim());

// Only legacy games with a real owner may omit delivery. Ownerless games must
// explicitly choose: management/creator alone never determine delivery.
function prizeFulfillment(game, shop, secondaryIndex = null) {
  const ownership = gameOwnership(game, shop);
  if (!ownership.valid) throw Error('Proprietaire du jeu incoherent.');
  const definition = secondaryIndex == null ? null : game.secondary_prizes?.[secondaryIndex];
  const value = definition?.fulfillment_type ?? game.fulfillment_type ??
    (ownership.ownerPath ? 'merchant' : null);
  if (!['merchant', 'partner', 'platform'].includes(value)) throw Error('Remise du lot non configuree.');
  if (value === 'merchant' && !ownership.ownerPath) throw Error('Compte commercant requis pour cette remise.');
  if (value === 'partner' && (ownership.ownerPath || !emailValid(shop.email))) {
    throw Error('La remise partenaire exige une enseigne sans compte et un email valide.');
  }
  return value;
}
module.exports = {prizeFulfillment, emailValid};
