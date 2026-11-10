// Suppression d'un compte joueur par l'Admin (1.1.4), contre les emulateurs
// Firestore et Auth uniquement (lifecycle_helpers.cjs).
const {test, assert, admin, db, ft, functions, client, assertFails, assertSucceeds} =
  require('./lifecycle_helpers.cjs');

const deletePlayer = ft.wrap(functions.adminDeletePlayerAccount);
const asAdmin = {auth: {uid: 'operator'}};
const valid = {confirmation: 'SUPPRIMER', reason: 'Demande du joueur par e-mail au support'};

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => error && error.code === code);
}

async function ensureAuthUser(uid, extra = {}) {
  try {
    await admin.auth().deleteUser(uid);
  } catch (_) {
    // absent
  }
  await admin.auth().createUser({uid, ...extra});
}

async function authExists(uid) {
  try {
    await admin.auth().getUser(uid);
    return true;
  } catch (error) {
    if (error.code === 'auth/user-not-found') return false;
    throw error;
  }
}

async function journal() {
  return (await db.collection('admin_account_deletions').get()).docs.map((doc) => doc.data());
}

test.beforeEach(async () => {
  await ensureAuthUser('player', {email: 'player@example.test'});
  await db.doc('users/player/fcm_tokens/t1').set({fcm_token: 'token-player'});
  await db.doc('users/player/marketing_consent_events/e1').set({event_type: 'granted'});
});

test('reserve aux administrateurs, rien n est supprime sinon', async () => {
  const data = {userId: 'player', ...valid};
  await expectCode(deletePlayer(data, {}), 'unauthenticated');
  await expectCode(deletePlayer(data, {auth: {uid: 'player'}}), 'permission-denied');
  await expectCode(deletePlayer(data, {auth: {uid: 'merchant'}}), 'permission-denied');
  assert.equal(await authExists('player'), true);
  assert.equal((await db.doc('users/player').get()).exists, true);
  assert.equal((await journal()).length, 0);
});

test('confirmation explicite et motif obligatoires', async () => {
  for (const data of [
    {userId: 'player', reason: valid.reason},
    {userId: 'player', reason: valid.reason, confirmation: 'supprimer'},
    {userId: 'player', reason: valid.reason, confirmation: true},
    {userId: 'player', confirmation: 'SUPPRIMER', reason: 'abc'},
    {userId: 'player', confirmation: 'SUPPRIMER'},
    {userId: 'users/player', ...valid},
  ]) {
    await expectCode(deletePlayer(data, asAdmin), 'invalid-argument');
  }
  assert.equal(await authExists('player'), true);
  assert.equal((await journal()).length, 0);
});

test('jamais un administrateur, ni un commercant, ni soi-meme', async () => {
  await expectCode(deletePlayer({userId: 'operator', ...valid}, asAdmin), 'failed-precondition');
  await expectCode(deletePlayer({userId: 'merchant', ...valid}, asAdmin), 'failed-precondition');
  await ensureAuthUser('claim-admin');
  await admin.auth().setCustomUserClaims('claim-admin', {admin: true});
  await expectCode(deletePlayer({userId: 'claim-admin', ...valid}, asAdmin), 'failed-precondition');
  assert.equal(await authExists('claim-admin'), true);
  assert.equal((await journal()).length, 0);
});

test('compte complet : connexion supprimee, donnees effacees, preuve conservee, journal', async () => {
  const result = await deletePlayer({userId: 'player', ...valid}, asAdmin);
  assert.equal(result.authDeleted, true);
  assert.equal(result.profileDeleted, true);
  assert.equal(result.consentEventsRetained, 1);
  assert.equal(await authExists('player'), false);
  assert.equal((await db.doc('users/player').get()).exists, false);
  assert.equal((await db.collection('users/player/fcm_tokens').get()).size, 0);
  assert.equal((await db.collection('users/player/marketing_consent_events').get()).size, 1);
  const [entry] = await journal();
  assert.deepEqual(Object.keys(entry).sort(), ['auth_account_found', 'completed_at',
    'consent_events_retained', 'deleted_by', 'deleted_uid', 'profile_found', 'reason',
    'requested_at', 'status']);
  assert.equal(entry.status, 'completed');
  assert.equal(entry.deleted_uid, 'player');
  assert.equal(entry.deleted_by, 'operator');
  assert.ok(!JSON.stringify(entry).includes('player@example.test'));
});

test('fiche orpheline sans compte de connexion : fiche effacee', async () => {
  await admin.auth().deleteUser('player');
  const result = await deletePlayer({userId: 'player', ...valid}, asAdmin);
  assert.equal(result.authDeleted, false);
  assert.equal(result.profileDeleted, true);
  assert.equal((await db.doc('users/player').get()).exists, false);
});

test('compte de connexion sans fiche (ancien bouton) : compte supprime', async () => {
  await db.doc('users/player').delete();
  const result = await deletePlayer({userId: 'player', ...valid}, asAdmin);
  assert.equal(result.authDeleted, true);
  assert.equal(result.profileDeleted, false);
  assert.equal(await authExists('player'), false);
});

test('compte inconnu : not-found, aucune trace', async () => {
  await expectCode(deletePlayer({userId: 'nobody', ...valid}, asAdmin), 'not-found');
  assert.equal((await journal()).length, 0);
});

test('journal : lecture admin seulement, aucune ecriture client', async () => {
  await deletePlayer({userId: 'player', ...valid}, asAdmin);
  const [doc] = (await db.collection('admin_account_deletions').get()).docs;
  await assertSucceeds(client('operator').doc(`admin_account_deletions/${doc.id}`).get());
  await assertFails(client('other').doc(`admin_account_deletions/${doc.id}`).get());
  await assertFails(client('operator').doc(`admin_account_deletions/${doc.id}`).update({reason: 'x'}));
  await assertFails(client('operator').collection('admin_account_deletions').add({deleted_uid: 'x'}));
});
