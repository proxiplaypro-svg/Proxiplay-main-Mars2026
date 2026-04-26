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
  defaultReferralExpirationDays,
  defaultShareState,
  generateUniqueInviteCode,
  isAllGamesUntilMidnightReward,
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

// Temporary development bypass. Keep as a fallback only.
const TEMP_ADMIN_UID = 'CKRlhsC8x2cUUsUPFy4rG67CyJHG2';

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
  if (auth.token.admin === true || auth.uid === TEMP_ADMIN_UID) {
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

    const [inviterGrantedSnap, inviteeGrantedSnap, eventSnap] =
      await Promise.all([
        transaction.get(
          refs
            .referrals()
            .where('inviterUid', '==', referral.inviterUid)
            .where('rewardStatus', '==', 'granted'),
        ),
        transaction.get(
          refs
            .referrals()
            .where('inviteeUid', '==', referral.inviteeUid)
            .where('rewardStatus', '==', 'granted'),
        ),
        transaction.get(eventRef),
      ]);

    if (eventSnap.exists) {
      return { granted: false, reason: 'event_exists' };
    }
    if (inviterGrantedSnap.size >= campaign.maxRewardsPerUser) {
      transaction.update(referralRef, {
        rewardStatus: 'blocked',
        metadata: {
          ...(referral.metadata ?? {}),
          blockReason: 'max_rewards_per_user_reached',
        },
      });
      return { granted: false, reason: 'max_rewards_per_user_reached' };
    }
    if (inviteeGrantedSnap.size >= campaign.maxRewardsPerInvitee) {
      transaction.update(referralRef, {
        rewardStatus: 'blocked',
        metadata: {
          ...(referral.metadata ?? {}),
          blockReason: 'max_rewards_per_invitee_reached',
        },
      });
      return { granted: false, reason: 'max_rewards_per_invitee_reached' };
    }

    transaction.set(
      eventRef,
      buildRewardEvent(referral.inviterUid, referralId, campaign, grantedBy),
    );
    await applyRewardToUser(
      transaction,
      referral.inviterUid,
      referral.rewardType,
      referral.rewardValue,
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
    if (isAllGamesUntilMidnightReward(referral.rewardType)) {
      followUpTasks.push(
        queueUserPushNotification({
          docId: `share_promo_reward_${referralId}`,
          title: '🎉 Ton parrainage a fonctionne !',
          body: 'Tu peux maintenant jouer à tous les jeux jusqu à minuit.',
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
      message = 'Un ami n a pas encore finalise son inscription.';
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
          : 'Plus qu une chance disponible';
      message = 'Invitez un proche pour continuer a jouer.';
      action = 'lowRemainingPlaysInvite';
    } else if (campaignActive) {
      kind = 'defaultInvite';
      title = campaign.title;
      message = campaign.message;
      action = 'defaultInvite';
    }

    return {
      showBanner: kind != null,
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

      const stateSnap = await refs.shareState(auth.uid).get();
      const state = stateSnap.exists
        ? { ...defaultShareState, ...stateSnap.data() }
        : defaultShareState;
      if (state.grantedCount >= campaign.maxRewardsPerUser) {
        throw new functions.https.HttpsError(
          'resource-exhausted',
          'Your reward quota has been reached.',
        );
      }

      const userSnap = await refs.user(auth.uid).get();
      const userData = userSnap.data() ?? {};
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

      return {
        referralId: referralRef.id,
        inviteCode,
        shareMessage: buildShareMessage(campaign, inviteCode),
        shareLink: buildShareLink(inviteCode),
      };
    },
  );

export const registerReferralAcceptance = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = normalizeString(data?.inviteCode);
    if (!inviteCode) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'inviteCode is required.',
      );
    }

    const referralQuery = await refs
      .referrals()
      .where('inviteCode', '==', inviteCode)
      .limit(1)
      .get();
    if (referralQuery.empty) {
      throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }

    const campaign = await loadCampaign();
    const referralRef = referralQuery.docs[0].ref;
    const acceptanceResult = await db.runTransaction(async (transaction) => {
      const [referralSnap, inviteeUserSnap, existingInviteeReferralSnap] =
          await Promise.all([
        transaction.get(referralRef),
        transaction.get(refs.user(auth.uid)),
        transaction.get(refs.referrals().where('inviteeUid', '==', auth.uid).limit(1)),
      ]);
      const referral = referralSnap.data() as ReferralRecord;
      if (referral.inviterUid === auth.uid) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Self-referrals are not allowed.',
        );
      }
      if (!existingInviteeReferralSnap.empty) {
        throw new functions.https.HttpsError(
          'already-exists',
          'A referral has already been used for this account.',
        );
      }
      if (referral.status !== 'pending' || referral.inviteeUid) {
        throw new functions.https.HttpsError(
          'already-exists',
          'This referral has already been accepted.',
        );
      }

      const rewardStatus =
        campaign.requireInviteeSignup && !inviteeUserSnap.exists
          ? 'blocked'
          : 'available';
      transaction.update(referralRef, {
        inviteeUid: auth.uid,
        status: 'accepted',
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedFromDeviceId: normalizeNullableString(
          data?.acceptedFromDeviceId,
        ),
        rewardStatus,
      });
      return { inviterUid: referral.inviterUid, rewardStatus };
    });

    await Promise.all([
      recomputeShareState(acceptanceResult.inviterUid),
      recomputeAdminStats(),
    ]);

    if (acceptanceResult.rewardStatus === 'available') {
      await grantReferralRewardInternal(
        referralRef.id,
        'system/registerReferralAcceptance',
      );
    }

    return {
      success: true,
      referralId: referralRef.id,
    };
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
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - defaultReferralExpirationDays * 24 * 60 * 60 * 1000,
    );
    const pendingSnap = await refs
      .referrals()
      .where('status', '==', 'pending')
      .where('createdAt', '<=', cutoff)
      .limit(300)
      .get();

    if (pendingSnap.empty) {
      return null;
    }

    const batch = db.batch();
    const inviterUids = new Set<string>();
    pendingSnap.docs.forEach((doc) => {
      const referral = doc.data() as ReferralRecord;
      inviterUids.add(referral.inviterUid);
      batch.update(doc.ref, {
        status: 'expired',
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    await batch.commit();

    await Promise.all([
      ...Array.from(inviterUids).map((uid) => recomputeShareState(uid)),
      recomputeAdminStats(),
    ]);
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

