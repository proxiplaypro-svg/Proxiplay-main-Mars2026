const {prepareReferralReward, processReferralReward, retryPendingReferralRewards, pendingRef} = require('../../referral_reward_queue');
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {
  applyRewardToUser,
  buildActiveCampaign,
  buildRewardEvent,
  buildShareLink,
  buildShareMessage,
  campaignId,
  db,
  defaultAdminStats,
  defaultShareState,
  generateUniqueInviteCode,
  getNextMidnightTimestamp,
  isAllGamesUntilMidnightReward,
  isRewardPlayable,
  isCampaignActive,
  normalizeNullableString,
  normalizeNumber,
  normalizeString,
  paths,
  queueUserPushNotification,
  recomputeAdminStats,
  recomputeShareState,
  refs,
  region,
  toTimestamp,
} from './firestore';
import {
  AdminUpsertSharePromoInput,
  CreateReferralInput,
  CreateReferralResponse, GetSharePromoStateResponse,
  ReferralRecord,
  SharePromoConfig,
} from './types';
import { addReferralGameTicket, findActiveReferralGame, reconcileReferralGameTickets } from './referral_games';
import {
  acceptReferralForNewAccount,
  accountBelongsToOperation,
  authCreationMs,
  emailRegistryKey,
  emailRegistryRef,
  findGoogleAccount,
  googleSignupRef,
  isAccountCreationSession,
  isLegacyTransitionOpen,
  isRegistryEntryActive,
  kEmailRegistryRetentionMs,
  NewAccountReferralOutcome,
  readUnverifiedGoogleClaims,
  signInWithGoogleIdToken,
} from './new_account_referral';

export { remindUsersWithRemainingDailyPlays } from './daily_plays_reminder';

// The anti-abuse registry key (HMAC of the address) is a Secret Manager value,
// bound by name only to the functions that need it, like the Stripe secrets,
// so that deploying any other function never requires it.
const kReferralSecrets = ['REFERRAL_EMAIL_HMAC_KEY'];

// Wording while a referral game runs: a referral then gives the inviter a draw
// ticket (no "all games until midnight" access).
export const kReferralGameInviteMessage = 'Invitez un ami et gagnez un ticket pour le tirage au sort !';
export function buildReferralGameShareMessage(inviteCode: string): string {
  return 'Rejoins-moi sur ProxiPlay avec mon code de parrainage ' + inviteCode + ' ! ' +
    'Quand ton inscription est validée, c’est moi qui gagne un ticket pour le tirage au sort.';
}

// An unreadable state (e.g. two games active at once) counts as running, so
// the "until midnight" promise is never shown when it may not apply.
async function isReferralGameRunning(): Promise<boolean> {
  try {
    return (await findActiveReferralGame()) != null;
  } catch (_) {
    return true;
  }
}

type CallableAuth = NonNullable<functions.https.CallableContext['auth']>;

function requireAuth(request: functions.https.CallableContext): CallableAuth {
  const { auth } = request;
  if (!auth?.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }
  return auth;
}

async function requireAdmin(
  context: functions.https.CallableContext,
): Promise<string> {
  const auth = requireAuth(context);
  if (auth.token.admin === true) {
    return auth.uid;
  }
  const userSnap = await refs.user(auth.uid).get();
  const userData = userSnap.data() ?? {};
  const userRole =
    normalizeString((userData as { user_role?: unknown }).user_role) ||
    normalizeString((userData as { userRole?: unknown }).userRole);
  if (userRole === 'admin') {
    return auth.uid;
  }
  throw new functions.https.HttpsError(
    'permission-denied',
    'Admin privileges are required.',
  );
}

async function loadCampaign(): Promise<SharePromoConfig> {
  const campaignSnap = await refs.sharePromoConfig().get();
  return buildActiveCampaign(
    (campaignSnap.exists ? campaignSnap.data() : undefined) as
      | Partial<SharePromoConfig>
      | undefined,
  );
}

async function grantReferralRewardInternal(
  referralId: string,
  grantedBy: string,
): Promise<{ granted: boolean; reason?: string }> {
  const campaign = await loadCampaign();
  const referralRef = refs.referral(referralId);
  const eventRef = refs.rewardEvent(referralId);

  const result = await db.runTransaction(async (transaction) => {
    const referralSnap = await transaction.get(referralRef);
    if (!referralSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }

    const referral = referralSnap.data() as ReferralRecord;
    if (referral.rewardStatus === 'granted') {
      return { granted: false, reason: 'already_granted' };
    }
    if (referral.status !== 'accepted' || !referral.inviteeUid) {
      return { granted: false, reason: 'referral_not_eligible' };
    }
    if (referral.rewardStatus === 'blocked' &&
        referral.metadata?.blockReason !== 'max_rewards_per_user_reached' &&
        referral.metadata?.blockReason !== 'max_rewards_per_invitee_reached') {
      return { granted: false, reason: 'reward_blocked' };
    }
    if (!isAllGamesUntilMidnightReward(referral.rewardType) &&
        (!isRewardPlayable(referral.rewardType) || referral.rewardValue <= 0)) {
      return { granted: false, reason: 'unsupported_reward' };
    }
    const inviter = await transaction.get(refs.user(referral.inviterUid));
    const account = inviter.data();
    if (!inviter.exists || require('../../prize_integrity').excluded(account)) {
      return {granted:false, reason:'inviter_ineligible'};
    }
    const durableReward = await transaction.get(pendingRef(referralId) as admin.firestore.DocumentReference);
    if (durableReward.exists && durableReward.data()?.mode === 'game' &&
        durableReward.data()?.classic_and_game !== true) {
      return {granted:false, reason:'game_reward_managed'};
    }

    const [inviteeGrantedSnap, eventSnap] =
      await Promise.all([
        transaction.get(
          refs
            .referrals()
            .where('inviteeUid', '==', referral.inviteeUid)
            .where('rewardStatus', '==', 'granted').limit(1),
        ),
        transaction.get(eventRef),
      ]);

    if (eventSnap.exists) {
      return { granted: false, reason: 'event_exists' };
    }
    if (!inviteeGrantedSnap.empty) {
      return { granted: false, reason: 'invitee_already_rewarded' };
    }

    const newRule = referral.metadata?.playerRewardRuleVersion === 2;
    if (newRule && !referral.acceptedAt) {
      return {granted: false, reason: 'missing_acceptance_date'};
    }
    const deadline = newRule && referral.acceptedAt
      ? getNextMidnightTimestamp(referral.acceptedAt)
      : undefined;
    const existingAccess = account?.allGamesAccessUntil;
    const accessUntil = deadline && existingAccess?.toMillis &&
      existingAccess.toMillis() > deadline.toMillis() ? existingAccess : deadline;
    const previousReferralAccess = account?.referralBonusExpiresAt;
    const referralAccessUntil = deadline && previousReferralAccess?.toMillis &&
      previousReferralAccess.toMillis() > deadline.toMillis() ? previousReferralAccess : deadline;

    transaction.set(
      eventRef,
      buildRewardEvent(referral.inviterUid, referralId,
        {...campaign, rewardType: referral.rewardType, rewardValue: referral.rewardValue}, grantedBy),
    );
    await applyRewardToUser(
      transaction,
      referral.inviterUid,
      referral.rewardType,
      referral.rewardValue,
      accessUntil,
      referralAccessUntil,
    );
    transaction.set(
      refs.shareState(referral.inviterUid),
      {
        grantedCount: admin.firestore.FieldValue.increment(1),
        rewardAvailable: false,
        lastRewardAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    transaction.update(referralRef, {
      rewardStatus: 'granted',
      rewardGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { granted: true };
  });

  if ('granted' in result && result.granted) {
    const referralSnap = await referralRef.get();
    const referral = referralSnap.data() as ReferralRecord;
    const followUpTasks: Promise<unknown>[] = [
      recomputeShareState(referral.inviterUid),
      recomputeAdminStats(),
    ];
    const validAccess = referral.metadata?.playerRewardRuleVersion !== 2 ||
      (referral.acceptedAt != null &&
        getNextMidnightTimestamp(referral.acceptedAt).toMillis() > Date.now());
    if (isAllGamesUntilMidnightReward(referral.rewardType) && validAccess) {
      followUpTasks.push(
        queueUserPushNotification({
          docId: `share_promo_reward_${referralId}`,
          title: '🎉 Ton parrainage a fonctionné !',
          body: 'Tu peux maintenant jouer à tous les jeux jusqu’à minuit.',
          userUid: referral.inviterUid,
          createdBy: grantedBy,
        }),
      );
    }
    await Promise.all(followUpTasks);
  }
  return result;
}

export const getSharePromoState = functions
  .region(region)
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (_data, context): Promise<GetSharePromoStateResponse> => {
    const auth = requireAuth(context);
    const [campaign, shareStateSnap, userSnap] = await Promise.all([
      loadCampaign(),
      refs.shareState(auth.uid).get(),
      refs.user(auth.uid).get(),
    ]);
    const userData = userSnap.data() ?? {};

    const shareState = shareStateSnap.exists
      ? { ...defaultShareState, ...shareStateSnap.data() }
      : defaultShareState;
    const remainingPart = normalizeNumber(userData.remaining_part, 0);
    const campaignActive = isCampaignActive(campaign);

    let kind: string | null = null;
    let title: string | null = null;
    let message: string | null = null;
    let action: string | null = null;

    if (shareState.rewardAvailable) {
      kind = 'rewardAvailable';
      title = 'Récompense disponible';
      message = 'Votre bonus de parrainage est disponible.';
      action = 'rewardAvailable';
    } else if (shareState.pendingCount > 0) {
      kind = 'friendPending';
      title = 'Invitation en attente';
      message = 'Un ami n’a pas encore finalisé son inscription.';
      action = 'friendPending';
    } else if (campaignActive && campaign.kind !== 'defaultInvite') {
      kind = 'specialCampaign';
      title = campaign.title;
      message = campaign.message;
      action = 'specialCampaign';
    } else if (campaignActive && remainingPart <= 1) {
      kind = 'lowRemainingPlaysInvite';
      title = remainingPart <= 0
          ? 'Plus de chances disponibles'
          : 'Plus qu’une chance disponible';
      message = 'Invitez un proche pour continuer à jouer.';
      action = 'lowRemainingPlaysInvite';
    } else if (campaignActive) {
      kind = 'defaultInvite';
      title = campaign.title;
      message = campaign.message;
      action = 'defaultInvite';
    }

    // During a referral game a new referral gives a draw ticket instead of
    // the "all games until midnight" access this banner promises, so it is
    // hidden (the referral game card invites instead). Unknown state hides it.
    const referralGameActive = await isReferralGameRunning();
    if (referralGameActive && kind != null) message = kReferralGameInviteMessage;

    return {
      showBanner: kind != null && !referralGameActive,
      referralGameActive,
      kind,
      title,
      message,
      ctaText: kind == null ? null : campaign.ctaText,
      action,
      campaign:
          kind == null
              ? null
              : {
                id: campaignId,
                rewardType: campaign.rewardType,
                rewardValue: campaign.rewardValue,
              },
    };
  });

export const createReferral = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(
    async (
      data: CreateReferralInput,
      context,
    ): Promise<CreateReferralResponse> => {
      const auth = requireAuth(context);
      const campaign = await loadCampaign();
      if (!isCampaignActive(campaign)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'No active share campaign is available.',
        );
      }

      const userSnap = await refs.user(auth.uid).get();
      const userData = userSnap.data() ?? {};
      const inviterRole = normalizeString(userData.user_role) || normalizeString(userData.userRole);
      if (!userSnap.exists || inviterRole !== 'joueur' ||
          require('../../prize_integrity').excluded(userData)) {
        throw new functions.https.HttpsError('permission-denied', 'A player account is required.');
      }
      const inviterPseudo =
        normalizeNullableString(userData.pseudo) ??
        normalizeNullableString(userData.display_name) ??
        normalizeNullableString(userData.first_name);
      const inviteCode = await generateUniqueInviteCode();
      const referralRef = refs.referrals().doc();
      const referral: ReferralRecord = {
        campaignId,
        inviterUid: auth.uid,
        inviterPseudo,
        inviteeUid: null,
        inviteeContact: normalizeNullableString(data?.inviteeContact),
        inviteCode,
        shareChannel: normalizeString(data?.shareChannel) || 'generic',
        status: 'pending',
        rewardStatus: 'not_earned',
        rewardType: campaign.rewardType,
        rewardValue: campaign.rewardValue,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedAt: null,
        rewardGrantedAt: null,
        expiredAt: null,
        createdFromDeviceId: normalizeNullableString(data?.createdFromDeviceId),
        acceptedFromDeviceId: null,
        metadata: data?.metadata ?? {},
      };

      await referralRef.set(referral);
      await Promise.all([
        refs.shareState(auth.uid).set(
          {
            pendingCount: admin.firestore.FieldValue.increment(1),
            lastReferralAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
        recomputeAdminStats(),
      ]);

      const referralGameActive = await isReferralGameRunning();
      return {
        referralId: referralRef.id,
        inviteCode,
        shareMessage: referralGameActive ?
          buildReferralGameShareMessage(inviteCode) : buildShareMessage(campaign, inviteCode),
        shareLink: buildShareLink(inviteCode),
        referralGameActive,
      };
    },
  );

// Referral signup operations are server-owned and contain no password.
export const createReferralEmailAccount = functions.region(region)
  .runWith({timeoutSeconds: 60, memory: '256MB', secrets: kReferralSecrets})
  .https.onCall(async (data, context) => {
    const crypto = require('crypto');
    const hash = (value: string): string => crypto.createHash('sha256').update(value).digest('hex');
    const requestId = typeof data?.requestId === 'string' ? data.requestId : '';
    const email = typeof data?.email === 'string' ? data.email.trim().toLowerCase() : '';
    const password = typeof data?.password === 'string' ? data.password : '';
    const inviteCode = normalizeString(data?.inviteCode);
    if (!/^[0-9a-f-]{36}$/i.test(requestId) || !email.includes('@') || email.length > 254 ||
        password.length < 6 || password.length > 128 || !inviteCode || inviteCode.length > 128) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid signup details.');
    }
    // The framework-resolved address depends on the deployment proxy configuration.
    // Verify it before rollout; never log credentials or the raw address.
    const ip = context.rawRequest?.ip || context.rawRequest?.socket?.remoteAddress;
    if (!ip) throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    const now = Date.now();
    const rate = db.collection('_referral_signup_rate').doc(hash(ip));
    await db.runTransaction(async tx => {
      const previous = (await tx.get(rate)).data() ?? {};
      const start = Number(previous.start) || 0;
      const count = now >= start && now-start < 60000 ? Number(previous.count)||0 : 0;
      if(count >= 5) throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
      tx.set(rate,{start:count ? start : now,count:count+1});
    });
    const found = await refs.referrals().where('inviteCode','==',inviteCode).limit(1).get();
    if(found.empty) throw new functions.https.HttpsError('not-found','Referral not found.');
    const referralRef = found.docs[0].ref;
    // A shared per-invitation quota also limits distributed attempts against a
    // valid code. This supplements the network quota; it is not attestation.
    const codeRate = db.collection('_referral_signup_code_rate').doc(hash(referralRef.id));
    await db.runTransaction(async tx => {
      const previous = (await tx.get(codeRate)).data() ?? {};
      const start = Number(previous.start) || 0;
      const count = now >= start && now-start < 60000 ? Number(previous.count)||0 : 0;
      if(count >= 10) throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
      tx.set(codeRate,{start:count ? start : now,count:count+1});
    });
    const operationRef = db.collection('_referral_signup_operations').doc(hash(requestId));
    const uid = 'ref_' + hash(requestId).slice(0, 48);
    // A deleted account recreated with the same address is new for Firebase,
    // not for ProxiPlay: refused before any account is created.
    const registryRef = emailRegistryRef(emailRegistryKey(email));
    const blocked = isRegistryEntryActive(await registryRef.get(), Date.now()) &&
      !(await operationRef.get()).exists;
    if (blocked) {
      throw new functions.https.HttpsError('failed-precondition', 'Referral unavailable.',
        {reason: 'email_not_eligible', accountCreated: false});
    }
    await db.runTransaction(async tx => {
      const [opSnap, referralSnap] = await Promise.all([tx.get(operationRef),tx.get(referralRef)]);
      const op = opSnap.data();
      const referral = referralSnap.data() as ReferralRecord | undefined;
      if(op) {
        if(op.uid !== uid || op.emailHash !== hash(email) || op.referralId !== referralRef.id)
          throw new functions.https.HttpsError('failed-precondition','Signup details changed.');
        return;
      }
      if(!referral || referral.status !== 'pending' || referral.inviteeUid)
        throw new functions.https.HttpsError('failed-precondition','Referral unavailable.', {reason:'referral_unavailable', accountCreated:false});
      tx.create(operationRef,{uid,emailHash:hash(email),referralId:referralRef.id,status:'pending',createdAt:admin.firestore.FieldValue.serverTimestamp()});
    });
    try {
      await admin.auth().createUser({uid,email,password});
    } catch (error: any) {
      // Only recover our server-assigned UID, never a pre-existing account found
      // by email. Other Auth errors leave the operation retryable.
      let user: admin.auth.UserRecord | undefined;
      try { user = await admin.auth().getUser(uid); } catch (_) { /* no matching UID */ }
      if(!user || user.email?.trim().toLowerCase() !== email) {
        if(error?.code === 'auth/email-already-exists')
          throw new functions.https.HttpsError('already-exists','Account already exists.', {reason:'email_exists', accountCreated:false});
        throw new functions.https.HttpsError('unavailable','Could not create account.');
      }
    }
    const result = await db.runTransaction(async tx => {
      const [opSnap, referralSnap, existing, registrySnap] = await Promise.all([
        tx.get(operationRef),tx.get(referralRef),tx.get(refs.referrals().where('inviteeUid','==',uid).limit(1)),
        tx.get(registryRef),
      ]);
      const op=opSnap.data(), referral=referralSnap.data() as ReferralRecord | undefined;
      if(!op || op.uid!==uid || op.emailHash!==hash(email) || op.referralId!==referralRef.id || !referral)
        throw new functions.https.HttpsError('failed-precondition','Invalid signup operation.');
      if(referral.status==='accepted' && referral.inviteeUid===uid)
        return {inviterUid:referral.inviterUid};
      if(referral.inviterUid===uid || !existing.empty || referral.status!=='pending' || referral.inviteeUid ||
          isRegistryEntryActive(registrySnap, Date.now()))
        throw new functions.https.HttpsError('already-exists','Referral unavailable.', {reason:'referral_unavailable', accountCreated:true});
      const acceptedAt=admin.firestore.Timestamp.now();
      // During an active referral game the ticket replaces the classic reward.
      const event=await prepareReferralReward(tx,referralRef.id,referral.inviterUid,acceptedAt);
      tx.create(pendingRef(referralRef.id),event);
      tx.update(referralRef,{inviteeUid:uid,status:'accepted',acceptedAt,rewardStatus:'available',
        rewardType:'all_games_until_midnight',rewardValue:1,
        metadata:{...(referral.metadata ?? {}),playerRewardRuleVersion:2}});
      tx.set(registryRef,{kind:'referred',created_at:acceptedAt,
        expires_at:admin.firestore.Timestamp.fromMillis(acceptedAt.toMillis()+kEmailRegistryRetentionMs)});
      tx.update(operationRef,{status:'completed',completedAt:admin.firestore.FieldValue.serverTimestamp()});
      return {inviterUid:referral.inviterUid};
    });
    try { await processReferralReward(referralRef.id,grantReferralRewardInternal); }
    catch (_) { functions.logger.error('REFERRAL_REWARD_DEFERRED', {referralId:referralRef.id}); }
    try { await Promise.all([recomputeShareState(result.inviterUid),recomputeAdminStats()]); }
    catch (_) { functions.logger.warn('REFERRAL_STATS_DEFERRED'); }
    return {success:true};
  });

async function findPendingReferralByCode(inviteCode: string): Promise<FirebaseFirestore.DocumentReference> {
  const referralQuery = await refs.referrals().where('inviteCode', '==', inviteCode).limit(1).get();
  if (referralQuery.empty) {
    throw new functions.https.HttpsError('not-found', 'Referral not found.');
  }
  return referralQuery.docs[0].ref;
}

// Reward processing and stats after a durable acceptance. Both are retried
// by the scheduled worker if they fail here.
async function afterNewAccountReferral(referralId: string, outcome: NewAccountReferralOutcome): Promise<void> {
  if (!outcome.accepted) return;
  try { await processReferralReward(referralId, grantReferralRewardInternal); }
  catch (_) { functions.logger.error('REFERRAL_REWARD_DEFERRED', {referralId}); }
  try { await Promise.all([recomputeShareState(outcome.inviterUid), recomputeAdminStats()]); }
  catch (_) { functions.logger.warn('REFERRAL_STATS_DEFERRED'); }
}

// Transition only, for app 1.1.1 which creates the account itself and sends
// the code afterwards (app 1.1.2 never calls this). Closed 4 weeks after the
// real publication of 1.1.2 (app_config/referral_signup).
export const registerReferralAcceptance = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB', secrets: kReferralSecrets })
  .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = normalizeString(data?.inviteCode);
    if (!inviteCode) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'inviteCode is required.',
      );
    }
    if (!(await isLegacyTransitionOpen(Date.now()))) {
      throw new functions.https.HttpsError('failed-precondition',
        'Referral codes are reserved to newly created accounts.', {reason: 'update_required'});
    }
    const referralRef = await findPendingReferralByCode(inviteCode);
    let user: admin.auth.UserRecord;
    try {
      user = await admin.auth().getUser(auth.uid);
    } catch (_) {
      throw new functions.https.HttpsError('failed-precondition', 'Referral codes are reserved to newly created accounts.');
    }
    const creationMs = Date.parse(user.metadata.creationTime);
    const inviteeSnap = await refs.user(auth.uid).get();
    const invitee = inviteeSnap.data() ?? {};
    // Only the session that created the account, before any game: an
    // existing account entering a code never counts, whatever its profile.
    if (!user.email || !isAccountCreationSession(auth.token.auth_time, creationMs) ||
        Number(invitee.games_played_count) > 0 || invitee.last_real_activity_at != null) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Referral codes are reserved to newly created accounts.',
      );
    }
    const outcome = await acceptReferralForNewAccount({
      referralRef,
      uid: auth.uid,
      emailKey: emailRegistryKey(user.email),
      referralFields: {acceptedFromDeviceId: normalizeNullableString(data?.acceptedFromDeviceId)},
    });
    if (!outcome.accepted) {
      const code = outcome.reason === 'self_referral' || outcome.reason === 'email_not_eligible' ?
        'failed-precondition' : 'already-exists';
      throw new functions.https.HttpsError(code, 'Referral unavailable.', {reason: outcome.reason});
    }
    await afterNewAccountReferral(referralRef.id, outcome);
    return {
      success: true,
      referralId: referralRef.id,
    };
  });

// Google signup with a referral code (app 1.1.2). The app obtains the Google
// ID token, calls this function BEFORE its own Firebase sign-in, then signs in
// with the same token. Firebase decides whether the account is new.
// Statuses: accepted | existing_account | not_eligible | refused.
// Never deletes an account: after a failure the operation is resumed by the
// next call or by the scheduled worker.
export const createReferralGoogleAccount = functions.region(region)
  .runWith({timeoutSeconds: 60, memory: '256MB', secrets: kReferralSecrets})
  .https.onCall(async (data, context) => {
    const crypto = require('crypto');
    const hash = (value: string): string => crypto.createHash('sha256').update(value).digest('hex');
    const idToken = typeof data?.idToken === 'string' ? data.idToken : '';
    const inviteCode = normalizeString(data?.inviteCode);
    const claims = idToken.length <= 8192 ? readUnverifiedGoogleClaims(idToken) : null;
    if (!claims || !inviteCode || inviteCode.length > 128) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid signup details.');
    }
    const ip = context.rawRequest?.ip || context.rawRequest?.socket?.remoteAddress;
    if (!ip) throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    const now = Date.now();
    const rate = db.collection('_referral_signup_rate').doc(hash(ip));
    await db.runTransaction(async tx => {
      const previous = (await tx.get(rate)).data() ?? {};
      const start = Number(previous.start) || 0;
      const count = now >= start && now-start < 60000 ? Number(previous.count)||0 : 0;
      if(count >= 5) throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
      tx.set(rate,{start:count ? start : now,count:count+1});
    });

    const operationRef = googleSignupRef(claims.sub);
    let op = (await operationRef.get()).data();
    if (op?.status === 'completed') {
      // Same person calling again: only answered after proving the identity.
      const idp = await signInWithGoogleIdToken(idToken);
      if (idp.sub !== claims.sub || idp.uid !== op.uid) {
        throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
      }
      return {status: op.outcome === 'accepted' ? 'accepted' : 'refused'};
    }
    if (!op) {
      const referralRef = await findPendingReferralByCode(inviteCode);
      const referral = (await referralRef.get()).data() as ReferralRecord | undefined;
      if (!referral || referral.status !== 'pending' || referral.inviteeUid) {
        throw new functions.https.HttpsError('failed-precondition', 'Referral unavailable.', {reason: 'referral_unavailable'});
      }
      const emailKey = emailRegistryKey(claims.email);
      if (isRegistryEntryActive(await emailRegistryRef(emailKey).get(), Date.now())) {
        return {status: 'not_eligible'};
      }
      // The operation is opened only once Firebase has no account for this
      // Google identity or address. An existing account never gets one.
      const checkedAbsentAt = Date.now();
      if (await findGoogleAccount(claims)) {
        return {status: 'existing_account'};
      }
      try {
        await operationRef.create({
          status: 'pending', googleSub: claims.sub, referralId: referralRef.id, emailKey,
          checkedAbsentAt, created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error: any) {
        if (error?.code !== 6) throw error; // 6 = ALREADY_EXISTS: concurrent call.
      }
      op = (await operationRef.get()).data();
      if (!op) throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    }

    // Firebase creates the account (or not) and says which. Identity is
    // established here: the operation must belong to this Google account.
    const idp = await signInWithGoogleIdToken(idToken);
    if (idp.sub !== op.googleSub) {
      throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
    }
    const outcome = await completeGoogleReferralSignup(operationRef, op, idp.uid, idp.isNewUser);
    return {status: outcome.accepted ? 'accepted' : outcome.reason === 'existing_account' ? 'existing_account' : 'refused'};
  });

async function completeGoogleReferralSignup(
  operationRef: FirebaseFirestore.DocumentReference,
  op: FirebaseFirestore.DocumentData,
  uid: string,
  reportedNew: boolean,
): Promise<NewAccountReferralOutcome> {
  if (op.uid && op.uid !== uid) {
    return {accepted: false, reason: 'operation_mismatch'};
  }
  const owned = reportedNew || op.uid === uid ||
    accountBelongsToOperation(await authCreationMs(uid), Number(op.checkedAbsentAt));
  if (!owned) {
    await operationRef.update({status: 'completed', outcome: 'refused', reason: 'existing_account', uid});
    return {accepted: false, reason: 'existing_account'};
  }
  // Recorded first: a crash below leaves a resumable operation with its uid.
  if (!op.uid) await operationRef.update({uid});
  const referralRef = refs.referrals().doc(op.referralId);
  const outcome = await acceptReferralForNewAccount({referralRef, uid, emailKey: op.emailKey, operationRef});
  await afterNewAccountReferral(referralRef.id, outcome);
  return outcome;
}

// Scheduled recovery of Google signups interrupted after the operation was
// opened (app closed, network lost, function crash). Never deletes anything.
const kGoogleSignupAbandonMs = 60 * 60 * 1000;
export async function resumeGoogleReferralSignups(nowMs = Date.now()): Promise<{resumed: number; abandoned: number}> {
  const pending = await db.collection('_referral_google_signups').where('status', '==', 'pending').limit(50).get();
  let resumed = 0, abandoned = 0;
  for (const doc of pending.docs) {
    const op = doc.data();
    if (nowMs - Number(op.checkedAbsentAt) < 2 * 60 * 1000) continue; // Leave the live call finish.
    try {
      let uid = typeof op.uid === 'string' ? op.uid : '';
      if (!uid) {
        try {
          uid = (await admin.auth().getUserByProviderUid('google.com', op.googleSub)).uid;
        } catch (error: any) {
          if (error?.code !== 'auth/user-not-found') throw error;
        }
      }
      if (!uid) {
        // No account was ever created for this operation.
        if (nowMs - Number(op.checkedAbsentAt) >= kGoogleSignupAbandonMs) {
          await doc.ref.update({status: 'completed', outcome: 'abandoned'});
          abandoned++;
        }
        continue;
      }
      await completeGoogleReferralSignup(doc.ref, op, uid, false);
      resumed++;
    } catch (_) {
      functions.logger.error('REFERRAL_GOOGLE_SIGNUP_RESUME_FAILED', {operation: doc.id});
    }
  }
  return {resumed, abandoned};
}


export const adminReconcileReferralGameTickets = functions
  .region(region)
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .https.onCall(async (data, context) => {
    await requireAdmin(context);
    const gameId = normalizeString(data?.gameId);
    if (!gameId || gameId.includes('/')) {
      throw new functions.https.HttpsError('invalid-argument', 'gameId is required.');
    }
    return reconcileReferralGameTickets(gameId);
  });

export const grantReferralReward = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    const adminUid = await requireAdmin(context);
    const referralId = normalizeString(data?.referralId);
    if (!referralId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'referralId is required.',
      );
    }
    return grantReferralRewardInternal(referralId, `admin/${adminUid}`);
  });

export const expireOldReferrals = functions
  .region(region)
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('every 24 hours')
  .timeZone('Europe/Paris')
  .onRun(async () => {
    // Keep the deployed schedule compatible, but never expire invitations.
    // Existing records, including previously expired ones, are untouched.
    return null;
  });

export const adminUpsertSharePromo = functions
  .region(region)
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data: AdminUpsertSharePromoInput, context) => {
    const adminUid = await requireAdmin(context);
    const startAt = toTimestamp(data?.startAt);
    const endAt = toTimestamp(data?.endAt);
    if (startAt && endAt && startAt.toMillis() >= endAt.toMillis()) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'startAt must be before endAt.',
      );
    }

    const payload = buildActiveCampaign({
      enabled: data?.enabled,
      kind: data?.kind,
      title: data?.title,
      message: data?.message,
      ctaText: data?.ctaText,
      startAt,
      endAt,
      rewardType: data?.rewardType,
      rewardValue: data?.rewardValue,
      maxRewardsPerUser: data?.maxRewardsPerUser,
      maxRewardsPerInvitee: data?.maxRewardsPerInvitee,
      requireInviteeSignup: data?.requireInviteeSignup,
      audience: data?.audience,
      isDraft: data?.isDraft,
      priority: data?.priority,
      updatedBy: adminUid,
    });

    await refs.sharePromoConfig().set(
      {
        ...payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await recomputeAdminStats();
    return {
      success: true,
      path: paths.sharePromoConfig,
      campaignId,
    };
  });

export const adminGetSharePromoConfig = functions
  .region(region)
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (_data, context) => {
    await requireAdmin(context);
    const campaign = await loadCampaign();
    return {
      ...campaign,
      startAt: campaign.startAt?.toMillis() ?? null,
      endAt: campaign.endAt?.toMillis() ?? null,
    };
  });

export const adminGetSharePromoStats = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (_data, context) => {
    await requireAdmin(context);
    const [stats, recentReferrals, recentRewards, acceptedReferrals] =
      await Promise.all([
        recomputeAdminStats(),
        refs.referrals().orderBy('createdAt', 'desc').limit(20).get(),
        refs.rewardEvents().orderBy('createdAt', 'desc').limit(20).get(),
        refs
          .referrals()
          .where('status', '==', 'accepted')
          .orderBy('createdAt', 'desc')
          .limit(100)
          .get(),
      ]);

    const topInvitersMap = new Map<string, number>();
    acceptedReferrals.docs.forEach((doc) => {
      const inviterUid = normalizeString(doc.get('inviterUid'));
      topInvitersMap.set(inviterUid, (topInvitersMap.get(inviterUid) ?? 0) + 1);
    });

    return {
      stats: stats ?? defaultAdminStats,
      recentReferrals: recentReferrals.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      })),
      recentRewards: recentRewards.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      })),
      topInviters: Array.from(topInvitersMap.entries())
        .map(([uid, acceptedCount]) => ({ uid, acceptedCount }))
        .sort((a, b) => b.acceptedCount - a.acceptedCount)
        .slice(0, 10),
    };
  });


export const retryReferralRewards = functions.region(region).runWith({timeoutSeconds:540,memory:'512MB'}).pubsub.schedule('every 1 minutes').onRun(async () => {
  // Google signups first: a resumed acceptance enqueues its reward below.
  await resumeGoogleReferralSignups();
  return retryPendingReferralRewards(grantReferralRewardInternal);
});
