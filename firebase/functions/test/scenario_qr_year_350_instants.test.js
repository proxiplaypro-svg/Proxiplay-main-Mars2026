// End-to-end scenario: a QR-only game from 1 January to 31 December with 45
// different secondary prizes and 350 instant winners, created like the Admin
// does, then a full year of in-shop scans. Isolated demo emulator only.
const {test, assert, db, ft, functions, participate, verifyPrize, client} = require('./lifecycle_helpers.cjs');
const {drawMainPrize} = require('../main_prize_draw');
const {searchMerchantPrizeCodesCore: searchCodes, syncPrizeSearchCodeCore: syncSearch} = require('../merchant_prizes');
const admin = require('firebase-admin');

const GAME = 'year_qr';
const START = '2027-01-01T00:00:00+01:00';
const END = '2027-12-31T23:59:59+01:00';
const at = (iso) => admin.firestore.Timestamp.fromDate(new Date(iso));
const setNow = (iso) => { process.env.LIFECYCLE_TEST_NOW = new Date(iso).toISOString(); };
const generate = ft.wrap(functions.generateInstantWinnersForGame);
const issueQr = ft.wrap(require('../game_qr_access').issueGameQrAccess);
const operator = {auth: {uid: 'operator'}};

// 45 different prizes, 350 occurrences: 35 x 8 + 10 x 7.
const PRIZES = Array.from({length: 45}, (_, i) => ({
  name: `Lot ${String(i + 1).padStart(2, '0')}`,
  description: `Description du lot ${i + 1}`,
  presentation: `Description du lot ${i + 1}`,
  count: i < 35 ? 8 : 7,
  image: '',
}));

// Deterministic pseudo-random scan times, for reproducible runs.
function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 2 ** 32; };
}

async function createLikeAdmin() {
  setNow('2026-11-15T10:00:00Z');
  // Same document as the Admin "Nouveau jeu" form (lib/firebase/gamesQueries.ts).
  await db.doc(`games/${GAME}`).set({
    title: 'Jeu de l’année', name: 'Jeu de l’année', description: 'Gros lot de fin d’année',
    create_by: db.doc('users/operator'), merchantId: 'shop', merchant_id: 'shop',
    merchantName: 'Fixture', enseigne_name: 'Fixture', enseigne_id: db.doc('enseignes/shop'),
    merchantRef: db.doc('enseignes/shop'),
    startDate: at(START), start_date: at(START), endDate: at(END), end_date: at(END),
    game_type: 'scratcher', type: 'standard', access_mode: 'qr_only',
    created_time: at('2026-11-15T10:00:00Z'), hasWinner: false, imageUrl: '', photo: '',
    sessionCount: 0, partiesCount: 0, hasMainPrize: true, secondary_prizes: PRIZES,
    prohibited_for_minors: false, restrictedToAdults: false,
    qr_link: `https://play.proxiplay.fr/j/${GAME}`, qr_target: 'game_detail', qr_version: 2,
    views: 0, favorites: 0, participations: 0,
    status: 'brouillon', visible_public: false, isPrivate: false,
  });
  await db.doc(`games/${GAME}`).update({prize_usage_deadline: at('2028-01-31T23:59:59+01:00')});
}

async function prepareGame() {
  await createLikeAdmin();
  const generated = await generate({gameId: GAME}, operator);
  assert.equal(generated.createdCount, 350, JSON.stringify(generated));
  const {token} = await issueQr({gameId: GAME}, operator);
  // Admin activation.
  await db.doc(`games/${GAME}`).update({status: 'actif', visible_public: true});
  return token;
}

async function instants() {
  return (await db.collection(`games/${GAME}/instant_winners`).get()).docs.map((d) => ({id: d.id, ...d.data()}));
}

async function secondaryPrizes() {
  return (await db.collection('prizes').where('game_id', '==', db.doc(`games/${GAME}`)).get()).docs
    .map((d) => ({id: d.id, ...d.data()}))
    .filter((p) => p.prize_type !== 'principal' && p.type !== 'main');
}

test('the calendar: 350 instants, 45 prizes, all inside the year, created like the Admin', async () => {
  await prepareGame();
  const all = await instants();
  assert.equal(all.length, 350);
  assert.equal(new Set(all.map((i) => i.id)).size, 350, 'unique instants');
  const start = new Date(START).getTime(), end = new Date(END).getTime();
  for (const i of all) {
    const ms = i.date.toMillis();
    assert.ok(ms >= start && ms <= end, `instant ${i.id} inside the year`);
    assert.equal(i.hasWinner, false);
  }
  const byPrize = {};
  for (const i of all) byPrize[i.secondary_prize_name] = (byPrize[i.secondary_prize_name] || 0) + 1;
  assert.equal(Object.keys(byPrize).length, 45);
  for (const prize of PRIZES) assert.equal(byPrize[prize.name], prize.count, prize.name);
  // Spread over the year: every month gets instants.
  const months = new Set(all.map((i) => new Date(i.date.toMillis()).toISOString().slice(0, 7)));
  assert.ok(months.size >= 12, `${months.size} months covered`);
  // A second generation never duplicates.
  assert.equal((await generate({gameId: GAME}, operator)).createdCount, 0);
  assert.equal((await instants()).length, 350);
});

for (const playersPerDay of [1, 2, 5]) {
  test(`a full year with ${playersPerDay} player(s) a day: no error, every lot consistent`, async () => {
    const token = await prepareGame();
    for (let p = 0; p < playersPerDay; p++) {
      await db.doc(`users/p${p}`).set({user_role: 'joueur', first_name: `p${p}`, remaining_part: 0});
    }
    // Before the opening, without the QR token, and after the end: refused.
    setNow('2026-12-31T12:00:00+01:00');
    await assert.rejects(participate(GAME, 'p0', {from_qr: true, qr_token: token}));
    setNow('2027-01-02T12:00:00+01:00');
    await assert.rejects(participate(GAME, 'p0', {from_qr: true}), {code: 'failed-precondition'});

    const random = rng(1000 + playersPerDay);
    const unexpected = [];
    let plays = 0, wins = 0, slowest = 0;
    const day0 = new Date('2027-01-01T00:00:00+01:00').getTime();
    for (let day = 0; day < 365; day++) {
      for (let p = 0; p < playersPerDay; p++) {
        // A scan between 08:00 and 20:00, Paris time (UTC+1/+2 handled by the date math).
        const when = new Date(day0 + day * 86400000 + (8 + random() * 12) * 3600000);
        setNow(when.toISOString());
        const t0 = Date.now();
        try {
          const result = await participate(GAME, `p${p}`, {from_qr: true, qr_token: token});
          plays++;
          if (result.isWin) wins++;
          // Scanning again the same day is not a second play.
          if (day % 50 === 0) {
            const again = await participate(GAME, `p${p}`, {from_qr: true, qr_token: token});
            assert.equal(again.isWin === true && again.prize_id !== result.prize_id, false, 'no second win the same day');
          }
        } catch (error) {
          unexpected.push(`${when.toISOString()} p${p}: ${error.code || ''} ${error.message}`);
        }
        slowest = Math.max(slowest, Date.now() - t0);
      }
    }
    setNow('2028-01-01T10:00:00+01:00');
    await assert.rejects(participate(GAME, 'p0', {from_qr: true, qr_token: token}));
    assert.deepEqual(unexpected.slice(0, 5), [], `${unexpected.length} unexpected errors`);

    // Integrity of every awarded instant and lot.
    const all = await instants();
    const awarded = all.filter((i) => i.hasWinner === true);
    const lots = await secondaryPrizes();
    assert.equal(awarded.length, wins, 'one awarded instant per win');
    assert.equal(lots.length, wins, 'one lot per win');
    assert.equal(new Set(lots.map((l) => l.claim_code)).size, lots.length, 'unique claim codes');
    const byInstantPrize = {};
    for (const i of awarded) byInstantPrize[i.secondary_prize_name] = (byInstantPrize[i.secondary_prize_name] || 0) + 1;
    for (const prize of PRIZES) assert.ok((byInstantPrize[prize.name] || 0) <= prize.count, `${prize.name} never over-awarded`);
    for (const lot of lots) {
      assert.equal(lot.fulfillment_type, 'merchant');
      assert.ok(PRIZES.some((p) => p.name === lot.name), `lot name ${lot.name} is one of the 45 prizes`);
      assert.ok(lot.winner_id?.path?.startsWith('users/p'));
      const link = await db.doc(`${lot.winner_id.path}/my_lots/${lot.id}`).get();
      assert.ok(link.exists, `my_lots link for ${lot.id}`);
    }
    // Free scans: no chance was ever debited, none credited beyond bonuses.
    for (let p = 0; p < playersPerDay; p++) {
      const remaining = (await db.doc(`users/p${p}`).get()).data().remaining_part;
      assert.ok(remaining >= 0, `p${p} balance never negative (${remaining})`);
    }
    assert.equal((await db.doc(`games/${GAME}`).get()).data().participations, plays);

    // The merchant finds and hands over lots won any time of the year.
    const sample = [lots[0], lots[Math.floor(lots.length / 2)], lots[lots.length - 1]].filter(Boolean);
    for (const lot of sample) {
      await syncSearch(db.doc(`prizes/${lot.id}`));
      assert.deepEqual((await searchCodes('merchant', lot.claim_code)).ids, [lot.id]);
      assert.deepEqual((await searchCodes('other', lot.claim_code)).ids, []);
    }
    await verifyPrize(sample[0].id, {winner: sample[0].winner_id.id});

    // Main prize drawn after the end, among the year's participants.
    const draw = await drawMainPrize(GAME, {now: at('2028-01-01T00:30:00+01:00')});
    assert.ok(draw.prizeId, JSON.stringify(draw));

    const left = 350 - wins;
    console.log(`SCENARIO ${playersPerDay}/jour: ${plays} parties, ${wins} lots gagnés, ${left} instants non distribués, appel le plus lent ${slowest} ms`);
  });
}
