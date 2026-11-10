// Annonce de la reserve de parties bonus (1.1.4) : notification push
// unique preparee (jamais envoyee par un declencheur), groupe "Players",
// et messages de gain et d'anniversaire sans « aujourd'hui ».
// Emulateurs uniquement (lifecycle_helpers.cjs).
const fs = require('node:fs');
const path = require('node:path');
const {test, assert, db} = require('./lifecycle_helpers.cjs');
const {
  buildBonusReserveAnnouncementRequest,
  kBonusReserveAnnouncement,
  kBonusReserveAnnouncementDocId,
  matchesTargetUserGroup,
  queueBonusReserveAnnouncement,
} = require('../bonus_reserve_announcement');
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
