// Effacement des donnees d'un compte supprime (onUserDeleted, 1.1.4),
// contre les emulateurs uniquement (lifecycle_helpers.cjs).
const {test, assert, admin, db, ft, functions} = require('./lifecycle_helpers.cjs');
const {kPurgedUserSubcollections, kRetainedUserSubcollections} =
  require('../deleted_user_cleanup');

const deleteAuthUser = ft.wrap(functions.onUserDeleted);

async function seedPlayerData(uid) {
  const user = db.doc(`users/${uid}`);
  await user.set({user_role: 'joueur', first_name: 'Alice', email: 'alice@example.test'});
  await user.collection('fcm_tokens').doc('t1').set({fcm_token: `token-${uid}`, device_type: 'Android'});
  await user.collection('favorite_games').doc('g1').set({game: db.doc('games/g1')});
  await user.collection('favorite_enseignes').doc('shop').set({enseigne: db.doc('enseignes/shop')});
  await user.collection('my_enseignes').doc('m1').set({enseigne: db.doc('enseignes/shop')});
  await user.collection('private').doc('share_state').set({shares: 2});
  await user.collection('birthday_corrections').doc('c1').set({reason: 'erreur'});
  await user.collection('marketing_consent_events').doc('e1').set({event_type: 'granted', enabled: true});
  await user.collection('my_lots').doc('l1').set({prize_id: db.doc('prizes/p1')});
  await user.collection('monthly_challenges').doc('2026-11').set({tickets: 1});
  // More than one batch of notifications.
  for (let start = 0; start < 450; start += 150) {
    const batch = db.batch();
    for (let i = start; i < start + 150; i += 1) {
      batch.set(user.collection('notifications').doc(`n${i}`), {title: 'x'});
    }
    await batch.commit();
  }
  await db.doc('prizes/p1').set({winner_id: user, claimed: false});
}

test('suppression du compte : donnees sans valeur de preuve effacees', async () => {
  await seedPlayerData('player');
  await deleteAuthUser({uid: 'player'});
  const user = db.doc('users/player');
  assert.equal((await user.get()).exists, false);
  for (const name of kPurgedUserSubcollections) {
    assert.equal((await user.collection(name).get()).size, 0, name);
  }
  // Broadcast pushes read every fcm_tokens document: none left for this account.
  const tokens = await db.collectionGroup('fcm_tokens').where('fcm_token', '==', 'token-player').get();
  assert.equal(tokens.size, 0);
});

test('suppression du compte : preuves et donnees en attente de decision conservees', async () => {
  await seedPlayerData('player');
  await deleteAuthUser({uid: 'player'});
  const user = db.doc('users/player');
  for (const name of kRetainedUserSubcollections) {
    assert.equal((await user.collection(name).get()).size, 1, name);
  }
  const consent = (await user.collection('marketing_consent_events').doc('e1').get()).data();
  assert.equal(consent.event_type, 'granted');
  assert.ok(consent.account_deleted_at instanceof admin.firestore.Timestamp);
  // The prize record is untouched (merchant delivery and claim history).
  assert.equal((await db.doc('prizes/p1').get()).data().winner_id.path, 'users/player');
});

test('les autres comptes ne sont pas touches', async () => {
  await seedPlayerData('player');
  await seedPlayerData('other');
  await deleteAuthUser({uid: 'player'});
  const other = db.doc('users/other');
  assert.equal((await other.get()).exists, true);
  assert.equal((await other.collection('fcm_tokens').get()).size, 1);
  assert.equal((await other.collection('notifications').get()).size, 450);
});

test('compte sans aucune donnee : suppression sans erreur', async () => {
  await deleteAuthUser({uid: 'ghost'});
  assert.equal((await db.doc('users/ghost').get()).exists, false);
});
