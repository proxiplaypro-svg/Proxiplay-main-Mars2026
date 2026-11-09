// Droits de publication lies a l'abonnement commercant : statuts, delai de
// grace et scripts de transition. Cote serveur uniquement : l'etat est
// affiche par le site proxiplay.fr (getMerchantBillingAccount, webhook).
// L'app mobile ne depend pas de Stripe : aucune regle Firestore ni aucun
// controle de publication n'en depend (exclus a l'integration 1.1.4).
// Emulateurs uniquement, aucun appel Stripe.
const {test, assert, admin, db} = require('./lifecycle_helpers.cjs');
const {
  computePublicationAccess,
  graceUntilMs,
  graceDays,
} = require('../merchant_publication_access');
const {
  planLegacyBackfill,
  applyLegacyBackfill,
  buildReport,
  setEnforcement,
} = require('../scripts/merchant_publication_access');

const kDay = 24 * 60 * 60 * 1000;
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const subscription = (fields) => db.doc('merchant_subscriptions/merchant').set(fields);

async function approve(uid = 'merchant') {
  await db.doc(`users/${uid}`).set({account_status: 'approved'}, {merge: true});
}

async function serverDraft(id = 'draft', extra = {}) {
  await db.doc(`games/${id}`).set({
    name: 'Jeu', status: 'active', visible_public: false, hasWinner: false, participations: 0,
    owner_id: db.doc('users/merchant'), enseigne_id: db.doc('enseignes/shop'), create_by: db.doc('users/merchant'),
    start_date: ts(Date.now() - kDay), end_date: ts(Date.now() + 30 * kDay), ...extra,
  });
}

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
