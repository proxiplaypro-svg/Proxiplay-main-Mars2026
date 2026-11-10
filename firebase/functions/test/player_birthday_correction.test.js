// Correction de la date de naissance par un administrateur (1.1.4), contre
// les emulateurs Firestore et Auth uniquement (lifecycle_helpers.cjs).
const {test, assert, db, ft, functions, game, participate} = require('./lifecycle_helpers.cjs');
const {isMarketingEmailRecipient} = require('../lib/marketing_consent_recipients');
const {_test: {parisMidnightMillis, parseIsoDate, ageBand}} = require('../player_birthday_correction');

const correct = ft.wrap(functions.adminCorrectPlayerBirthday);
const asAdmin = {auth: {uid: 'operator'}};
const kReason = 'Erreur de saisie signalee au support';

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => error && error.code === code);
}

async function corrections(uid = 'player') {
  return (await db.collection(`users/${uid}/birthday_corrections`).get()).docs.map((doc) => doc.data());
}

test('reserve aux administrateurs, sans aucune ecriture sinon', async () => {
  const data = {userId: 'player', birthday: '1990-05-18', reason: kReason};
  await expectCode(correct(data, {}), 'unauthenticated');
  await expectCode(correct(data, {auth: {uid: 'player'}}), 'permission-denied');
  await expectCode(correct(data, {auth: {uid: 'merchant'}}), 'permission-denied');
  assert.equal((await db.doc('users/player').get()).data().birthday, undefined);
  assert.equal((await corrections()).length, 0);
});

test('parametres invalides refuses : motif, date, joueur', async () => {
  const base = {userId: 'player', birthday: '1990-05-18', reason: kReason};
  await expectCode(correct({...base, reason: ''}, asAdmin), 'invalid-argument');
  await expectCode(correct({...base, reason: 'abc'}, asAdmin), 'invalid-argument');
  await expectCode(correct({...base, reason: 'x'.repeat(201)}, asAdmin), 'invalid-argument');
  for (const birthday of ['1990-02-30', '18/05/1990', '1899-12-31', '2999-01-01', '', 642981600000]) {
    await expectCode(correct({...base, birthday}, asAdmin), 'invalid-argument');
  }
  await expectCode(correct({...base, userId: 'users/player'}, asAdmin), 'invalid-argument');
  await expectCode(correct({...base, userId: 'nobody'}, asAdmin), 'not-found');
  await expectCode(correct({...base, userId: 'merchant'}, asAdmin), 'failed-precondition');
  assert.equal((await corrections()).length, 0);
});

test('correction : date a minuit (Paris), journal minimal sans aucune date', async () => {
  await db.doc('users/player').update({birthday: new Date('2012-03-03T23:00:00Z')});
  const result = await correct({userId: 'player', birthday: '1990-05-18', reason: `  ${kReason}  `}, asAdmin);
  assert.equal(result.changed, true);
  assert.equal(result.previousAgeBand, 'under_15');
  assert.equal(result.newAgeBand, '18_plus');
  assert.equal(result.marketingConsentWithdrawn, false);
  const user = (await db.doc('users/player').get()).data();
  assert.equal(user.birthday.toMillis(), Date.parse('1990-05-17T22:00:00Z'));
  const [log] = await corrections();
  assert.deepEqual(Object.keys(log).sort(), ['corrected_at', 'corrected_by', 'had_birthday',
    'marketing_consent_withdrawn', 'new_age_band', 'previous_age_band', 'reason']);
  assert.equal(log.corrected_by, 'operator');
  assert.equal(log.reason, kReason);
  assert.equal(log.had_birthday, true);
  assert.ok(!JSON.stringify(log).includes('1990') && !JSON.stringify(log).includes('2012'));
});

test('premiere saisie par un administrateur pour un joueur sans date', async () => {
  const result = await correct({userId: 'player', birthday: '2001-01-01', reason: kReason}, asAdmin);
  assert.equal(result.previousAgeBand, 'unknown');
  assert.equal((await corrections())[0].had_birthday, false);
});

test('meme jour : aucune ecriture ni journal', async () => {
  await db.doc('users/player').update({birthday: new Date('1990-05-17T22:00:00Z')});
  const result = await correct({userId: 'player', birthday: '1990-05-18', reason: kReason}, asAdmin);
  assert.equal(result.changed, false);
  assert.equal((await corrections()).length, 0);
});

test('moins de 15 ans : consentement marketing retire et trace dans la meme transaction', async () => {
  await db.doc('users/player').update({
    birthday: new Date('1990-05-17T22:00:00Z'),
    marketing_consent: {enabled: true, text_version: 'marketing-player-v1', source: 'signup',
      newsletter_eligibility: 'age_15_plus_confirmed'},
  });
  assert.equal(isMarketingEmailRecipient((await db.doc('users/player').get()).data()), true);
  const result = await correct({userId: 'player', birthday: '2015-06-01', reason: kReason}, asAdmin);
  assert.equal(result.marketingConsentWithdrawn, true);
  assert.equal(result.newAgeBand, 'under_15');
  const user = (await db.doc('users/player').get()).data();
  assert.equal(user.marketing_consent.enabled, false);
  assert.equal(user.marketing_consent.newsletter_eligibility, 'age_ineligible');
  assert.equal(user.marketing_consent.source, 'admin-birthday-correction');
  assert.equal(isMarketingEmailRecipient(user), false);
  const events = (await db.collection('users/player/marketing_consent_events').get()).docs.map((d) => d.data());
  assert.equal(events.length, 1);
  assert.equal(events[0].event_type, 'withdrawn');
  assert.equal(events[0].withdrawal_reason, 'birthday_correction_under_15');
  assert.ok(events[0].retention_until);
  assert.equal((await corrections())[0].marketing_consent_withdrawn, true);
});

test('15-17 ans : consentement conserve, aucun evenement marketing', async () => {
  await db.doc('users/player').update({
    birthday: new Date('1990-05-17T22:00:00Z'),
    marketing_consent: {enabled: true, newsletter_eligibility: 'age_15_plus_confirmed'},
  });
  const sixteen = new Date();
  const birthday = `${sixteen.getUTCFullYear() - 16}-01-01`;
  const result = await correct({userId: 'player', birthday, reason: kReason}, asAdmin);
  assert.equal(result.newAgeBand, '15_17');
  assert.equal(result.marketingConsentWithdrawn, false);
  assert.equal((await db.doc('users/player').get()).data().marketing_consent.enabled, true);
  assert.equal((await db.collection('users/player/marketing_consent_events').get()).size, 0);
});

test('restrictions d\'age reevaluees aussitot, lots deja gagnes conserves', async () => {
  await db.doc('users/player').update({birthday: new Date('1990-05-17T22:00:00Z')});
  await game('adult-1', {prohibited_for_minors: true});
  await game('adult-2', {prohibited_for_minors: true});
  await participate('adult-1');
  await db.doc('prizes/won-before').set({winner_id: db.doc('users/player'), game_id: db.doc('games/adult-1'),
    claimed: false, prize_type: 'secondary'});
  await correct({userId: 'player', birthday: '2015-06-01', reason: kReason}, asAdmin);
  await assert.rejects(participate('adult-2'), (error) => error.code === 'failed-precondition' &&
    /majeures/.test(error.message));
  const prize = (await db.doc('prizes/won-before').get()).data();
  assert.equal(prize.winner_id.path, 'users/player');
  assert.equal(prize.claimed, false);
});

test('suppression du compte (onUserDeleted) : document et journal supprimes', async () => {
  await db.doc('users/player').update({birthday: new Date('1990-05-17T22:00:00Z')});
  await correct({userId: 'player', birthday: '1991-05-18', reason: kReason}, asAdmin);
  assert.equal((await corrections()).length, 1);
  await ft.wrap(functions.onUserDeleted)({uid: 'player'});
  assert.equal((await db.doc('users/player').get()).exists, false);
  assert.equal((await corrections()).length, 0);
});

test('dates : minuit a Paris en hiver et en ete, dates calendaires strictes', () => {
  assert.equal(parisMidnightMillis(parseIsoDate('1990-01-15')), Date.parse('1990-01-14T23:00:00Z'));
  assert.equal(parisMidnightMillis(parseIsoDate('1990-07-15')), Date.parse('1990-07-14T22:00:00Z'));
  assert.equal(parseIsoDate('2000-02-29').day, 29);
  assert.equal(parseIsoDate('2001-02-29'), null);
  const now = new Date('2026-11-10T12:00:00Z');
  assert.equal(ageBand(new Date('2011-11-09T23:00:00Z'), now), '15_17');
  assert.equal(ageBand(new Date('2011-11-10T23:00:00Z'), now), 'under_15');
  assert.equal(ageBand(new Date('2008-11-09T23:00:00Z'), now), '18_plus');
  assert.equal(ageBand(null, now), 'unknown');
});
