// FAILLE 2 (audit global, phase 2) -- correction de la cause structurelle :
// gamePrizeOwnership() (merchant_ownership.js) posait owner_id == marchand
// des que l'enseigne du jeu avait un proprietaire, QUEL QUE SOIT le
// fulfillment_type. Pour 'partner' c'etait deja impossible en pratique
// (prizeFulfillment() refuse cette valeur quand un proprietaire existe),
// mais rien ne protegeait 'platform' : un marchand hebergeant son propre
// jeu avec fulfillment_type:'platform' obtenait quand meme un prize dont
// il "possedait" le owner_id, lisible via get()/list()/getMerchantPrizes
// avant la Phase 1 de ce chantier.
//
// Ce fichier prouve, via les VRAIS moteurs (drawMainPrize,
// participateInGameTransaction) et les VRAIES regles canoniques, que :
//  - un nouveau prize merchant garde owner_id == marchand (pas de regression) ;
//  - un nouveau prize partner/platform n'a plus jamais owner_id == marchand ;
//  - la defense en profondeur (Rules get/list, export CSV) ferme chaque
//    chemin de lecture pour ces lots, pour le marchand hebergeur precisement.
const {test, assert, db, game, instant, participate, client, assertFails, assertSucceeds, time, ft, functions} = require('./lifecycle_helpers.cjs');
const {drawMainPrize} = require('../main_prize_draw');
const {merchantPrizesPage} = require('../merchant_prizes');

const exportCsv = ft.wrap(functions.exportGameParticipantsCallable || require('../export_game_participants').exportGameParticipantsCallable);

async function setupPartnerShop(id = 'partner_shop') {
  await db.doc(`enseignes/${id}`).set({
    name: 'Enseigne partenaire', managed_by_admin: true, email: 'partner@example.com',
  });
  return db.doc(`enseignes/${id}`);
}

async function decodeExport(gameId, uid) {
  const result = await exportCsv({gameId, format: 'csv'}, {auth: {uid}});
  return Buffer.from(result.csvBase64, 'base64').toString('utf8');
}

// ---------------------------------------------------------------------
// 1. Tirage principal : les trois fulfillment_type.
// ---------------------------------------------------------------------
test('tirage principal, fulfillment_type merchant : owner_id == marchand (comportement inchange)', async () => {
  await game('g', {fulfillment_type: 'merchant'});
  await participate('g', 'player');
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  const prize = (await db.doc('prizes/' + result.prizeId).get()).data();
  assert.equal(prize.owner_id.path, 'users/merchant');
  assert.equal(prize.fulfillment_type, 'merchant');
});

test('tirage principal, fulfillment_type platform (enseigne appartenant au marchand) : owner_id absent', async () => {
  await game('g', {fulfillment_type: 'platform'});
  await participate('g', 'player');
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  const prize = (await db.doc('prizes/' + result.prizeId).get()).data();
  assert.equal(prize.owner_id, null, 'owner_id ne doit jamais etre le marchand pour un lot platform');
  assert.equal(prize.fulfillment_type, 'platform');
  // La boutique hote reste tracee : enseigne_id n'est pas confondu avec le
  // responsable de la remise.
  assert.equal(prize.enseigne_id.path, 'enseignes/shop');
});

test('tirage principal, fulfillment_type partner (enseigne geree admin, sans proprietaire) : owner_id absent', async () => {
  const partnerShop = await setupPartnerShop();
  await game('g', {owner_id: null, enseigne_id: partnerShop, fulfillment_type: 'partner'});
  await participate('g', 'player');
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  const prize = (await db.doc('prizes/' + result.prizeId).get()).data();
  assert.equal(prize.owner_id, null);
  assert.equal(prize.fulfillment_type, 'partner');
  assert.equal(prize.partner_ref.path, partnerShop.path);
});

// ---------------------------------------------------------------------
// 2. Lot instantane : les trois fulfillment_type.
// ---------------------------------------------------------------------
test('lot instantane, fulfillment_type merchant : owner_id == marchand (comportement inchange)', async () => {
  await game('g', {fulfillment_type: 'merchant'});
  await instant('g');
  const result = await participate('g', 'player');
  assert.equal(result.isWin, true);
  const prize = (await db.doc(result.prize_id).get()).data();
  assert.equal(prize.owner_id.path, 'users/merchant');
  assert.equal(prize.fulfillment_type, 'merchant');
});

test('lot instantane, fulfillment_type platform (enseigne appartenant au marchand) : owner_id absent', async () => {
  await game('g', {fulfillment_type: 'platform'});
  await instant('g');
  const result = await participate('g', 'player');
  assert.equal(result.isWin, true);
  const prize = (await db.doc(result.prize_id).get()).data();
  assert.equal(prize.owner_id, null);
  assert.equal(prize.fulfillment_type, 'platform');
  assert.equal(prize.enseigne_id.path, 'enseignes/shop');
});

test('lot instantane, fulfillment_type partner (enseigne geree admin, sans proprietaire) : owner_id absent', async () => {
  const partnerShop = await setupPartnerShop();
  await game('g', {owner_id: null, enseigne_id: partnerShop, fulfillment_type: 'partner'});
  await instant('g');
  const result = await participate('g', 'player');
  assert.equal(result.isWin, true);
  const prize = (await db.doc(result.prize_id).get()).data();
  assert.equal(prize.owner_id, null);
  assert.equal(prize.fulfillment_type, 'partner');
});

// ---------------------------------------------------------------------
// 3. SCENARIO LEGACY CRITIQUE -- platform : chaine complete avec le VRAI
// moteur, les VRAIES regles, et l'export reel.
// ---------------------------------------------------------------------
test('SCENARIO CRITIQUE platform : nouveau prize, ancienne query vide, get() refuse, export vide, gagnant/admin preserves', async () => {
  await game('g', {fulfillment_type: 'platform'});
  await participate('g', 'player');
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  const prizeId = result.prizeId;
  const prize = (await db.doc('prizes/' + prizeId).get()).data();

  // owner_id == null/absent.
  assert.equal(prize.owner_id, null);

  // L'ancienne requete historique ne retourne plus ce document.
  const legacyQuery = await client('merchant').collection('prizes')
    .where('owner_id', '==', client('merchant').doc('users/merchant')).get();
  assert.equal(legacyQuery.size, 0, "l'ancienne requete owner_id ne doit plus matcher ce lot platform");

  // get() direct refuse au marchand.
  await assertFails(client('merchant').doc('prizes/' + prizeId).get());

  // getMerchantPrizes ne le propose meme plus comme id candidat.
  const page = await merchantPrizesPage('merchant');
  assert.ok(!page.ids.includes(prizeId));

  // L'export CSV marchand ne contient ni le code ni le lot.
  const csv = await decodeExport('g', 'merchant');
  assert.ok(!csv.includes(prize.claim_code));

  // Le gagnant garde l'acces prevu par le modele actuel.
  await assertSucceeds(client('player').doc('prizes/' + prizeId).get());

  // Admin garde son acces.
  await assertSucceeds(client('operator').doc('prizes/' + prizeId).get());
});

test('SCENARIO CRITIQUE partner : nouveau prize, ancienne query vide, get() refuse, gagnant/admin preserves', async () => {
  // Pas d'assertion d'export ici : un jeu 'partner' vit par construction sur
  // une enseigne geree admin SANS proprietaire (prizeFulfillment() l'exige,
  // voir prize_fulfillment.js) -- aucun marchand ne "possede" ce jeu, donc
  // exportGameParticipantsCallable refuse deja l'appel pour 'merchant' en
  // amont (gameOwnership invalide), independamment du fulfillment_type du
  // prize. C'est le comportement d'ownership preexistant, pas celui teste
  // ici. Le scenario export/merchant pertinent est entierement couvert par
  // le cas 'platform' ci-dessus (ou l'enseigne appartient reellement au
  // marchand) et par export_game_participants.test.js.
  const partnerShop = await setupPartnerShop('partner_shop_2');
  await game('g', {owner_id: null, enseigne_id: partnerShop, fulfillment_type: 'partner'});
  await participate('g', 'player');
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  const prizeId = result.prizeId;
  const prize = (await db.doc('prizes/' + prizeId).get()).data();

  assert.equal(prize.owner_id, null);

  const legacyQuery = await client('merchant').collection('prizes')
    .where('owner_id', '==', client('merchant').doc('users/merchant')).get();
  assert.equal(legacyQuery.size, 0);

  await assertFails(client('merchant').doc('prizes/' + prizeId).get());

  const page = await merchantPrizesPage('merchant');
  assert.ok(!page.ids.includes(prizeId));

  await assertSucceeds(client('player').doc('prizes/' + prizeId).get());
  await assertSucceeds(client('operator').doc('prizes/' + prizeId).get());
});
