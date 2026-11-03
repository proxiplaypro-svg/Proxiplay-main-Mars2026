// Droits de publication lies a l'abonnement commercant : statuts, delai de
// grace, transition non destructive, regles Firestore et controle serveur.
// Emulateurs uniquement, aucun appel Stripe.
const {test, assert, admin, db, ft, functions, client, assertFails, assertSucceeds} =
  require('./lifecycle_helpers.cjs');
const {
  computePublicationAccess,
  graceUntilMs,
  graceDays,
  getMerchantPublicationAccessHandler,
} = require('../merchant_publication_access');
const {
  planLegacyBackfill,
  applyLegacyBackfill,
  buildReport,
  setEnforcement,
} = require('../scripts/merchant_publication_access');

const kDay = 24 * 60 * 60 * 1000;
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const enforce = (enabled = true) => db.doc('app_config/merchant_billing').set({enforce_publication_access: enabled});
const subscription = (fields) => db.doc('merchant_subscriptions/merchant').set(fields);

async function approve(uid = 'merchant') {
  await db.doc(`users/${uid}`).set({account_status: 'approved'}, {merge: true});
}

function draftGame(merchantDb) {
  return {
    owner_id: merchantDb.doc('users/merchant'),
    enseigne_id: merchantDb.doc('enseignes/shop'),
    create_by: merchantDb.doc('users/merchant'),
    name: 'Jeu du mois',
    visible_public: false,
    end_date: new Date(Date.now() + 30 * kDay),
  };
}

const createDraft = (id = 'draft') => client('merchant').doc(`games/${id}`).set(draftGame(client('merchant')));

async function serverDraft(id = 'draft', extra = {}) {
  await db.doc(`games/${id}`).set({
    name: 'Jeu', status: 'active', visible_public: false, hasWinner: false, participations: 0,
    owner_id: db.doc('users/merchant'), enseigne_id: db.doc('enseignes/shop'), create_by: db.doc('users/merchant'),
    start_date: ts(Date.now() - kDay), end_date: ts(Date.now() + 30 * kDay), ...extra,
  });
}
const publish = (id = 'draft', uid = 'merchant') =>
  ft.wrap(functions.generateInstantWinnersForGame)({gameId: id, publishOnSuccess: true}, {auth: {uid}});

// --- Statuts et delai de grace (fonctions pures) ------------------------------

test('explicit publication statuses', () => {
  const now = Date.UTC(2027, 0, 20);
  const cases = [
    [null, 'free', false],
    [{stripe_livemode: true, subscription_status: 'active'}, 'active', true],
    [{stripe_livemode: true, subscription_status: 'active', cancel_at_period_end: true}, 'active', true],
    [{stripe_livemode: true, subscription_status: 'trialing'}, 'active', true],
    [{legacy_access: {enabled: true}}, 'legacy', true],
    [{manual_access: {enabled: true, until: ts(now + kDay)}}, 'manual', true],
    [{manual_access: {enabled: true, until: ts(now - kDay)}}, 'free', false],
    [{stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(now + kDay)}, 'grace', true],
    [{stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(now - 1)}, 'suspended', false],
    [{stripe_livemode: true, subscription_status: 'unpaid', grace_until: ts(now - kDay)}, 'suspended', false],
    [{stripe_livemode: true, subscription_status: 'past_due'}, 'suspended', false],
    [{stripe_livemode: true, subscription_status: 'canceled'}, 'ended', false],
    [{stripe_livemode: true, subscription_status: 'incomplete'}, 'pending_payment', false],
    [{stripe_livemode: true, subscription_status: 'canceled', legacy_access: {enabled: true}}, 'legacy', true],
  ];
  for (const [doc, status, canPublish] of cases) {
    const access = computePublicationAccess(doc, now);
    assert.equal(access.status, status, JSON.stringify(doc));
    assert.equal(access.canPublish, canPublish, JSON.stringify(doc));
  }
});

test('production: only a LIVE Stripe status opens rights; TEST or unknown mode counts as no subscription', () => {
  const now = Date.UTC(2027, 0, 20);
  const prod = {sandbox: false};
  const cases = [
    [{stripe_livemode: true, subscription_status: 'active'}, 'active', true],
    [{stripe_livemode: false, subscription_status: 'active'}, 'free', false],
    // stripe_sandbox n'est jamais cru hors projet demo-, meme pose a la main.
    [{stripe_livemode: false, stripe_sandbox: true, subscription_status: 'active'}, 'free', false],
    [{subscription_status: 'active'}, 'free', false],
    [{stripe_livemode: false, subscription_status: 'past_due', grace_until: ts(now + kDay)}, 'free', false],
    // Les droits existants (Admin) ne dependent jamais du mode Stripe.
    [{stripe_livemode: false, subscription_status: 'active', legacy_access: {enabled: true}}, 'legacy', true],
    [{stripe_livemode: false, subscription_status: 'canceled', manual_access: {enabled: true, until: null}}, 'manual', true],
  ];
  for (const [doc, status, canPublish] of cases) {
    const access = computePublicationAccess(doc, now, prod);
    assert.equal(access.status, status, JSON.stringify(doc));
    assert.equal(access.canPublish, canPublish, JSON.stringify(doc));
  }
  // Emulateurs (demo-) : un abonnement TEST accepte par le serveur compte.
  assert.equal(computePublicationAccess(
    {stripe_livemode: false, stripe_sandbox: true, subscription_status: 'active'}, now, {sandbox: true}).status, 'active');
});

test('grace lasts 14 days from the unpaid due date by default, is configurable and never extended', () => {
  const due = Date.UTC(2027, 10, 2);
  assert.equal(graceDays(), 14);
  assert.equal(graceUntilMs(null, due), due + 14 * kDay);
  assert.equal(graceUntilMs(due + 3 * kDay, due + 10 * kDay), due + 3 * kDay, 'jamais repousse');
  process.env.MERCHANT_BILLING_GRACE_DAYS = '30';
  try {
    assert.equal(graceUntilMs(null, due), due + 30 * kDay);
  } finally {
    delete process.env.MERCHANT_BILLING_GRACE_DAYS;
  }
});

// --- Regles Firestore (creation d'un jeu par le commercant) -------------------

test('without enforcement, an approved merchant keeps creating games exactly as today', async () => {
  await approve();
  await assertSucceeds(createDraft());
});

test('enforced: a merchant without subscription cannot create a game; legacy, active, grace and manual can', async () => {
  await approve();
  await enforce();
  await assertFails(createDraft('free'));

  for (const [label, fields] of [
    ['legacy', {legacy_access: {enabled: true}}],
    ['active', {stripe_livemode: true, subscription_status: 'active'}],
    ['grace', {stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(Date.now() + 3 * kDay)}],
    ['manual', {manual_access: {enabled: true, until: null}}],
  ]) {
    await db.doc('merchant_subscriptions/merchant').delete();
    await subscription(fields);
    await assertSucceeds(createDraft(`ok_${label}`));
  }
});

test('enforced: expired grace, ended subscription or expired manual access block game creation', async () => {
  await approve();
  await enforce();
  for (const [label, fields] of [
    ['suspended', {stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(Date.now() - 1000)}],
    ['ended', {stripe_livemode: true, subscription_status: 'canceled'}],
    ['manual_expired', {manual_access: {enabled: true, until: ts(Date.now() - 1000)}}],
    ['pending_payment', {stripe_livemode: true, subscription_status: 'incomplete'}],
  ]) {
    await db.doc('merchant_subscriptions/merchant').delete();
    await subscription(fields);
    await assertFails(createDraft(`ko_${label}`));
  }
});

test('enforced: a TEST-mode subscription never opens publication (rules and server); legacy and manual still do', async () => {
  await approve();
  await enforce();
  for (const [label, fields] of [
    ['test_active', {stripe_livemode: false, subscription_status: 'active'}],
    ['test_trialing', {stripe_livemode: false, stripe_sandbox: false, subscription_status: 'trialing'}],
    ['no_mode', {subscription_status: 'active'}],
    ['test_grace', {stripe_livemode: false, subscription_status: 'past_due', grace_until: ts(Date.now() + 3 * kDay)}],
  ]) {
    await db.doc('merchant_subscriptions/merchant').delete();
    await subscription(fields);
    await assertFails(createDraft(`ko_${label}`));
    await serverDraft(`srv_${label}`);
    await assert.rejects(publish(`srv_${label}`), (err) => err.code === 'failed-precondition', label);
  }
  for (const [label, fields] of [
    ['legacy', {stripe_livemode: false, subscription_status: 'active', legacy_access: {enabled: true}}],
    ['manual', {stripe_livemode: false, subscription_status: 'active', manual_access: {enabled: true, until: null}}],
  ]) {
    await db.doc('merchant_subscriptions/merchant').delete();
    await subscription(fields);
    await assertSucceeds(createDraft(`ok_${label}`));
  }
});

test('enforcement is off by default: without app_config/merchant_billing nobody loses the right to publish', async () => {
  await approve();
  await db.doc('app_config/merchant_billing').delete();
  await subscription({stripe_livemode: false, subscription_status: 'canceled'});
  await assertSucceeds(createDraft('default_off'));
  await serverDraft('default_off_srv');
  assert.equal((await publish('default_off_srv')).published, true);
});

test('a merchant pending validation still cannot create games, whatever the subscription', async () => {
  await db.doc('users/merchant').set({account_status: 'pendingValidation'}, {merge: true});
  await subscription({stripe_livemode: true, subscription_status: 'active'});
  await assertFails(createDraft());
});

test('a merchant can never grant himself access nor switch enforcement off', async () => {
  await approve();
  await enforce();
  const merchantDb = client('merchant');
  await assertFails(merchantDb.doc('merchant_subscriptions/merchant').set({legacy_access: {enabled: true}}));
  await assertFails(merchantDb.doc('merchant_subscriptions/merchant').set({grace_until: new Date(Date.now() + kDay)}));
  await assertFails(merchantDb.doc('app_config/merchant_billing').set({enforce_publication_access: false}));
  await assertSucceeds(merchantDb.doc('app_config/merchant_billing').get());
});

test('a blocked merchant keeps reading, hiding and deleting his existing games (nothing is taken away)', async () => {
  await approve();
  await enforce();
  await serverDraft('old', {visible_public: true, end_date: ts(Date.now() - kDay)});
  const merchantDb = client('merchant');
  await assertSucceeds(merchantDb.doc('games/old').get());
  await assertSucceeds(merchantDb.doc('games/old').update({hidden_from_merchant_stats: true}));
});

// --- Controle serveur de la publication -----------------------------------

test('enforced: publication is refused server-side without rights, and the draft is kept intact', async () => {
  await approve();
  await enforce();
  await serverDraft();
  await assert.rejects(publish(), (err) => {
    assert.equal(err.code, 'failed-precondition');
    assert.equal(err.details.reason, 'subscription_required');
    return true;
  });
  const game = (await db.doc('games/draft').get()).data();
  assert.equal(game.visible_public, false, 'brouillon conserve, rien supprime');
});

test('enforced: legacy and active merchants publish; an admin is never blocked', async () => {
  await approve();
  await enforce();
  await subscription({legacy_access: {enabled: true}});
  await serverDraft('legacy_game');
  assert.equal((await publish('legacy_game')).published, true);

  await db.doc('merchant_subscriptions/merchant').set({stripe_livemode: true, subscription_status: 'active', legacy_access: {enabled: false}});
  await serverDraft('active_game');
  assert.equal((await publish('active_game')).published, true);

  await db.doc('merchant_subscriptions/merchant').delete();
  await serverDraft('admin_game');
  assert.equal((await publish('admin_game', 'operator')).published, true);
});

test('expired grace blocks publication; regularisation confirmed by Stripe restores it automatically', async () => {
  await approve();
  await enforce();
  await subscription({stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(Date.now() - 1000)});
  await serverDraft();
  await assert.rejects(publish(), (err) => err.code === 'failed-precondition');

  // Ce que le webhook ecrit apres invoice.paid (statut relu chez Stripe).
  await subscription({stripe_livemode: true, subscription_status: 'active', grace_until: null});
  assert.equal((await publish()).published, true);
});

test('a game already running is never interrupted by a suspension', async () => {
  await approve();
  await enforce();
  await subscription({stripe_livemode: true, subscription_status: 'unpaid', grace_until: ts(Date.now() - kDay)});
  await serverDraft('running', {visible_public: true});
  const result = await publish('running');
  assert.equal(result.published, true);
  assert.equal((await db.doc('games/running').get()).data().visible_public, true);
});

// --- Transition non destructive (script) ------------------------------------

test('legacy backfill keeps every existing approved merchant, is idempotent and purely additive', async () => {
  await approve('merchant');
  await db.doc('users/pending').set({user_role: 'commercant', account_status: 'pendingValidation'});
  await db.doc('users/other').set({account_status: 'approved'}, {merge: true});
  await db.doc('enseignes/other_shop').set({name: 'Autre', owner_id: db.doc('users/other')});
  await db.doc('users/player').set({account_status: 'approved'}, {merge: true}); // joueur sans enseigne
  await db.doc('merchant_subscriptions/other').set({manual_access: {enabled: true, reason: 'Historique'}, offer_id: 'custom'});

  const plan = await planLegacyBackfill(db);
  assert.deepEqual(plan.toGrant.map((row) => row.uid).sort(), ['merchant', 'other']);
  assert.equal(await applyLegacyBackfill(db, plan), 2);

  const other = (await db.doc('merchant_subscriptions/other').get()).data();
  assert.equal(other.legacy_access.enabled, true);
  assert.equal(other.manual_access.reason, 'Historique', 'activation manuelle conservee');
  assert.equal(other.offer_id, 'custom');
  assert.equal((await db.doc('merchant_subscriptions/pending').get()).exists, false);

  const again = await planLegacyBackfill(db);
  assert.equal(again.toGrant.length, 0);
  assert.equal(again.alreadyCovered.length, 2);
  assert.deepEqual((await planLegacyBackfill(db, {includePending: true})).toGrant.map((r) => r.uid), ['pending']);
});

test('enforcement cannot be switched on while an existing merchant would lose his rights', async () => {
  await approve();
  await assert.rejects(setEnforcement(db, true), /backfill-legacy/);
  assert.equal((await db.doc('app_config/merchant_billing').get()).exists, false);

  await applyLegacyBackfill(db, await planLegacyBackfill(db));
  await setEnforcement(db, true);
  assert.equal((await db.doc('app_config/merchant_billing').get()).data().enforce_publication_access, true);
  await assertSucceeds(createDraft('after_transition'));
});

test('the report flags merchants without rights who still have running games, without touching them', async () => {
  await approve();
  await subscription({stripe_livemode: true, subscription_status: 'past_due', grace_until: ts(Date.now() - kDay)});
  await serverDraft('running', {visible_public: true});
  const report = await buildReport(db);
  assert.equal(report.byStatus.suspended, 1);
  assert.deepEqual(report.needsDecision, [{uid: 'merchant', status: 'suspended', runningGames: ['running']}]);
  assert.equal((await db.doc('games/running').get()).data().visible_public, true);
});

// --- Information "abonnement requis" pour l'app -----------------------------

test('the app is told "refused" only when enforcement is on and access is denied', async () => {
  const ask = (uid = 'merchant') => getMerchantPublicationAccessHandler({}, {auth: {uid}});
  await assert.rejects(getMerchantPublicationAccessHandler({}, {auth: null}), (err) => err.code === 'unauthenticated');
  await approve();
  assert.deepEqual(await ask(), {enforced: false, allowed: true, status: 'free'}, 'controle inactif : rien ne change');
  await enforce();
  assert.deepEqual(await ask(), {enforced: true, allowed: false, status: 'free'});
  await subscription({legacy_access: {enabled: true}});
  assert.deepEqual(await ask(), {enforced: true, allowed: true, status: 'legacy'});
});

test('legacy rights of validated merchants never expire; pending accounts get none by default', async () => {
  await approve();
  await db.doc('users/pending').set({user_role: 'commercant', account_status: 'pendingValidation'});
  await db.doc('enseignes/pending_shop').set({name: 'En attente', owner: db.doc('users/pending')});
  await applyLegacyBackfill(db, await planLegacyBackfill(db));
  const legacy = (await db.doc('merchant_subscriptions/merchant').get()).data().legacy_access;
  assert.equal(legacy.enabled, true);
  assert.equal(legacy.until, undefined, 'aucune expiration');
  const farFuture = Date.UTC(2040, 0, 1);
  assert.equal(computePublicationAccess({legacy_access: legacy}, farFuture).canPublish, true);
  assert.equal((await db.doc('merchant_subscriptions/pending').get()).exists, false);
});
