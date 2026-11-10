// Annonce de la reserve de parties bonus (1.1.4) : notification push
// unique preparee (jamais envoyee par un declencheur), groupe "Players",
// et messages de gain et d'anniversaire sans « aujourd'hui ».
// Emulateurs uniquement (lifecycle_helpers.cjs).
const fs = require('node:fs');
const path = require('node:path');
const {test, assert, db, ft, functions} = require('./lifecycle_helpers.cjs');
const {
  buildBonusReserveAnnouncementRequest,
  kBonusReserveAnnouncement,
  kBonusReserveAnnouncementDocId,
  queueBonusReserveAnnouncement,
} = require('../bonus_reserve_announcement');
const {
  isPlayersGroupRecipient,
  matchesTargetUserGroup,
  selectPlayersGroupTokens,
} = require('../push_target_groups');
const {
  kDailyPlaysReminderMessage,
  shouldRemindDailyPlays,
} = require('../lib/share_promo/daily_plays_reminder');
const {kParticipationBonusMessage} = require('../play_balance');
const {kDefaultBirthdayMessage} = require('../lib/notifications/constants');
const {getBirthdayMessage} = require('../lib/notifications/runners/birthday_runner');

const kTodayOnly = /aujourd|avant minuit|jusqu.(?:à|a) minuit|du jour|expire/i;

test('le texte de la notification est celui valide', () => {
  assert.equal(kBonusReserveAnnouncement.title, '🎁 Vos parties bonus ne disparaissent plus !');
  assert.equal(kBonusReserveAnnouncement.body,
    'Conservez vos parties bonus et utilisez-les quand vous voulez. ' +
    'Mettez ProxiPlay à jour pour en profiter !');
  const doc = buildBonusReserveAnnouncementRequest({createdBy: 'users/op'});
  assert.equal(doc.notification_title, kBonusReserveAnnouncement.title);
  assert.equal(doc.notification_text, kBonusReserveAnnouncement.body);
  assert.equal(doc.target_user_group, 'Players');
  assert.equal(doc.user_refs, '');
  assert.equal(doc.status, 'started');
  assert.equal(doc.initial_page_name, 'HomeJoueurPage');
});

test('le groupe Players ne vise que les joueurs ; les autres groupes sont inchanges', () => {
  assert.equal(matchesTargetUserGroup('Players', 'joueur'), true);
  for (const role of ['commercant', 'admin', '']) {
    assert.equal(matchesTargetUserGroup('Players', role), false, role);
  }
  assert.equal(matchesTargetUserGroup('Admins', 'admin'), true);
  assert.equal(matchesTargetUserGroup('Admins', 'joueur'), false);
  assert.equal(matchesTargetUserGroup('Professionals', 'commercant'), true);
  assert.equal(matchesTargetUserGroup('Professionals', 'joueur'), false);
  assert.equal(matchesTargetUserGroup('NormalUsers', 'commercant'), true);
  assert.equal(matchesTargetUserGroup('NormalUsers', 'admin'), false);
  assert.equal(matchesTargetUserGroup('All', 'admin'), true);
  assert.equal(matchesTargetUserGroup('', 'commercant'), true);
});

test('la notification ne peut etre mise en file qu une seule fois', async () => {
  const docRef = db.doc(`ff_push_notifications/${kBonusReserveAnnouncementDocId}`);
  await docRef.delete();
  const first = await queueBonusReserveAnnouncement(db, {createdBy: 'users/op'});
  assert.equal(first.status, 'queued');
  const stored = (await docRef.get()).data();
  assert.equal(stored.notification_title, kBonusReserveAnnouncement.title);
  assert.equal(stored.target_user_group, 'Players');

  const second = await queueBonusReserveAnnouncement(db, {createdBy: 'users/other'});
  assert.equal(second.status, 'already_queued');
  assert.equal((await docRef.get()).data().created_by, 'users/op');
  await docRef.delete();
});

test('aucun code de production ne met la notification en file', () => {
  const root = path.join(__dirname, '..');
  const callers = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      if (['node_modules', 'test', 'scripts', '.git'].includes(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(js|ts)$/.test(entry.name) &&
        !full.endsWith('bonus_reserve_announcement.js') &&
        fs.readFileSync(full, 'utf8').includes('queueBonusReserveAnnouncement')) {
        callers.push(full);
      }
    }
  };
  walk(root);
  assert.deepEqual(callers, []);
});

test('les messages de gain et d anniversaire ne parlent plus de bonus du jour', () => {
  assert.ok(!kTodayOnly.test(kParticipationBonusMessage), kParticipationBonusMessage);
  assert.match(kParticipationBonusMessage, /conservées/);
  assert.ok(!kTodayOnly.test(kDefaultBirthdayMessage.body), kDefaultBirthdayMessage.body);
  assert.match(kDefaultBirthdayMessage.body, /conservées/);
  // Configuration de production (ancien texte « avantages du jour ») :
  // remplacee par le nouveau texte a l'envoi.
  const legacy = getBirthdayMessage({messagesByStatus: {default: {
    title: 'Joyeux anniversaire {firstName} 🎉',
    body: 'Profitez de vos avantages du jour et tentez votre chance !',
  }}}, {first_name: 'Lea'});
  assert.equal(legacy.title, 'Joyeux anniversaire Lea 🎉');
  assert.ok(!kTodayOnly.test(legacy.body), legacy.body);
});

test('groupe Players : profil joueur actif seulement', () => {
  assert.equal(isPlayersGroupRecipient({user_role: 'joueur'}), true);
  for (const user of [
    null, {}, {user_role: 'commercant'}, {user_role: 'admin'}, {user_role: ''},
    {user_role: 'joueur', deleted: true}, {user_role: 'joueur', auto_deleted: true},
    {user_role: 'joueur', account_status: 'suspended'},
    {user_role: 'joueur', account_status: 'rejected'},
    {user_role: 'joueur', player_status_cached: 'Suspendu'},
  ]) {
    assert.equal(isPlayersGroupRecipient(user), false, JSON.stringify(user));
  }
});

test('groupe Players : un telephone partage avec un commercant ou un admin est exclu', () => {
  const selected = selectPlayersGroupTokens([
    {token: 'joueur-seul', ref: 'users/a/fcm_tokens/x', eligible: true},
    {token: 'partage-commercant', ref: 'users/b/fcm_tokens/y', eligible: true},
    {token: 'partage-commercant', ref: 'users/m/fcm_tokens/y', eligible: false},
    {token: 'admin', ref: 'users/o/fcm_tokens/z', eligible: false},
    {token: 'deux-joueurs', ref: 'users/c/fcm_tokens/w', eligible: true},
    {token: 'deux-joueurs', ref: 'users/d/fcm_tokens/w', eligible: true},
    null,
  ]);
  assert.deepEqual(selected.map((item) => item.token), ['joueur-seul', 'deux-joueurs']);
  assert.equal(selected[1].refs.length, 2);
});

test('l envoi Players lit le role dans le profil, pas dans le jeton', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8')
    .replace(/\r\n/g, '\n');
  const start = source.indexOf('if (targetUserGroup === kPlayersUserGroup) {');
  assert.ok(start > 0);
  const branch = source.slice(start, source.indexOf('} else {', start));
  assert.ok(branch.includes('tokenDoc.ref.parent.parent.get()'));
  assert.ok(branch.includes('isPlayersGroupRecipient(userData)'));
  assert.ok(branch.includes('selectPlayersGroupTokens(entries)'));
  assert.ok(!branch.includes('user_role'));
});

test('rappel quotidien : texte qui distingue parties du jour et parties bonus', () => {
  assert.equal(kDailyPlaysReminderMessage.title, 'Il vous reste des parties du jour !');
  assert.equal(kDailyPlaysReminderMessage.body,
    'Jouez-les avant minuit. Vos parties bonus, elles, sont conservées.');
  assert.equal(shouldRemindDailyPlays({user_role: 'joueur', remaining_part: 2}), true);
  assert.equal(shouldRemindDailyPlays({remaining_part: 1}), true);
  for (const user of [
    {user_role: 'joueur', remaining_part: 0},
    {user_role: 'joueur', remaining_part: 0, bonus_part: 5},
    {user_role: 'joueur'},
    {user_role: 'commercant', remaining_part: 3},
    {user_role: 'admin', remaining_part: 3},
    undefined,
  ]) {
    assert.equal(shouldRemindDailyPlays(user), false, JSON.stringify(user));
  }
});

test('rappel quotidien : seuls les joueurs avec des parties du jour le recoivent', async () => {
  await db.doc('users/player').update({remaining_part: 2, bonus_part: 0});
  await db.doc('users/merchant').update({remaining_part: 3});
  await db.doc('users/other').update({remaining_part: 0});
  await db.doc('users/operator').update({remaining_part: 3});
  await db.doc('users/bonusOnly').set({user_role: 'joueur', remaining_part: 0, bonus_part: 6});
  const before = await db.collection('ff_push_notifications').get();
  await Promise.all(before.docs.map((doc) => doc.ref.delete()));

  await ft.wrap(functions.remindUsersWithRemainingDailyPlays)({});

  const sent = await db.collection('ff_push_notifications').get();
  assert.deepEqual(sent.docs.map((doc) => doc.data().user_refs), ['users/player']);
  const push = sent.docs[0].data();
  assert.equal(push.notification_title, kDailyPlaysReminderMessage.title);
  assert.equal(push.notification_text, kDailyPlaysReminderMessage.body);
  await Promise.all(sent.docs.map((doc) => doc.ref.delete()));
  await db.doc('users/bonusOnly').delete();
});
