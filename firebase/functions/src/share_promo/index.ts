import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
const nodemailer = require('nodemailer');
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
  pushNotificationsCollection,
  queueUserPushNotification,
  createUserInAppNotification,
  recomputeAdminStats,
  recomputeShareState,
  refs,
  region,
  toTimestamp,
} from './firestore';
import {
  AdminUpsertSharePromoInput,
  CreateReferralInput,
  CreateReferralResponse,
  GetSharePromoStateResponse,
  ReferralRecord,
  SharePromoConfig,
  ValidateReferralCodeInput,
  ValidateReferralCodeResponse,
} from './types';

// Temporary development bypass. Keep as a fallback only.
const TEMP_ADMIN_UID = 'CKRlhsC8x2cUUsUPFy4rG67CyJHG2';
const dailyPlaysReminderVariants = [
  {
    title: '🎮 Il vous reste des chances !',
    body: 'Tentez votre chance avant minuit 🍀',
  },
  {
    title: '🍀 Vos parties du jour vous attendent',
    body: 'Vous avez encore des chances à jouer aujourd’hui.',
  },
  {
    title: '🎯 Ne laissez pas vos parties expirer',
    body: 'Utilisez vos chances avant la fin de la journée.',
  },
  {
    title: '🎁 Des jeux vous attendent encore',
    body: 'Vous pouvez encore jouer sur ProxiPlay aujourd’hui.',
  },
  {
    title: '⏳ Il est encore temps de jouer',
    body: 'Vos chances du jour ne sont pas encore utilisées.',
  },
  {
    title: '🎮 Vous n’avez pas tout utilisé',
    body: 'Revenez tenter votre chance avant minuit.',
  },
  {
    title: '🍀 Encore des chances disponibles',
    body: 'Profitez-en tant qu’il est encore temps.',
  },
  {
    title: '🎯 Votre journée ProxiPlay n’est pas finie',
    body: 'Il vous reste encore des parties à jouer.',
  },
] as const;

function getParisDateKey(date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Paris',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function parseDailyReminderIndex(value: unknown): number | null {
  return Number.isInteger(value) ? Number(value) : null;
}

function pickDailyPlaysReminderVariant(lastIndex: number | null) {
  let index = Math.floor(Math.random() * dailyPlaysReminderVariants.length);
  if (
    dailyPlaysReminderVariants.length > 1 &&
    lastIndex !== null &&
    lastIndex >= 0 &&
    lastIndex < dailyPlaysReminderVariants.length &&
    index === lastIndex
  ) {
    index =
      (index +
        1 +
        Math.floor(Math.random() * (dailyPlaysReminderVariants.length - 1))) %
      dailyPlaysReminderVariants.length;
  }
  return {
    index,
    ...dailyPlaysReminderVariants[index],
  };
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


async function loadNotificationsConfig(): Promise<{
  dailyRemainingChancesReminderEnabled: boolean;
}> {
  const configSnap = await db.collection('app_config').doc('notifications').get();
  const configData = (configSnap.data() ?? {}) as {
    dailyRemainingChancesReminderEnabled?: unknown;
  };
  return {
    dailyRemainingChancesReminderEnabled:
      configData.dailyRemainingChancesReminderEnabled !== false,
  };
}


type SmtpMailer = {
  transporter: {
    sendMail: (options: Record<string, unknown>) => Promise<unknown>;
  };
  from: string;
  replyTo: string;
};

function getTrimmedString(value: unknown): string {
  return typeof value == 'string' ? value.trim() : '';
}

function createSmtpMailer(): SmtpMailer {
  const smtpConfig = functions.config().smtp || {};
  const host = getTrimmedString(smtpConfig.host);
  const port = Number(smtpConfig.port || 587);
  const secure =
    typeof smtpConfig.secure === 'boolean'
      ? smtpConfig.secure
      : String(smtpConfig.secure || '').toLowerCase() === 'true' || port === 465;
  const user = getTrimmedString(smtpConfig.user);
  const pass = typeof smtpConfig.pass === 'string' ? smtpConfig.pass : '';
  const fromEmail = getTrimmedString(smtpConfig.from_email);
  const fromName = getTrimmedString(smtpConfig.from_name);
  const replyTo = getTrimmedString(smtpConfig.reply_to);

  if (!host || !port || !user || !pass || !fromEmail || !fromName) {
    throw new Error('smtp_not_configured');
  }

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure,
    auth: { user, pass },
  });

  return {
    transporter,
    from: `${fromName} <${fromEmail}>`,
    replyTo,
  };
}

async function resolveUserEmail(uid: string): Promise<string> {
  const userSnap = await refs.user(uid).get();
  const userData = userSnap.data() ?? {};
  const emailFromDoc = getTrimmedString((userData as { email?: unknown }).email);
  if (emailFromDoc) {
    return emailFromDoc;
  }

  try {
    const authUser = await admin.auth().getUser(uid);
    return getTrimmedString(authUser.email);
  } catch (_) {
    return '';
  }
}

async function sendEmailNotification(
  mailer: SmtpMailer,
  to: string,
  subject: string,
  textBody: string,
): Promise<void> {
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text: textBody,
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

async function notifyInviterRewardByEmail(
  inviterUid: string,
  subject: string,
  body: string,
): Promise<void> {
  const recipientEmail = await resolveUserEmail(inviterUid);
  if (!recipientEmail) {
    console.log(`[share_promo] reward email skipped: missing_email uid=${inviterUid}`);
    return;
  }

  let mailer: SmtpMailer;
  try {
    mailer = createSmtpMailer();
  } catch (error) {
    console.log(
      `[share_promo] reward email skipped: smtp_unavailable uid=${inviterUid} error=${error}`,
    );
    return;
  }

  await sendEmailNotification(mailer, recipientEmail, subject, body);
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
      const notificationTitle = 'Bonne nouvelle !';
      const notificationBody =
        'Votre parrainage a ?t? valid?. Vous pouvez jouer ? tous les jeux jusqu?? minuit.';
      followUpTasks.push(
        queueUserPushNotification({
          docId: `share_promo_reward_${referralId}`,
          title: notificationTitle,
          body: notificationBody,
          userUid: referral.inviterUid,
          createdBy: grantedBy,
        }),
        createUserInAppNotification({
          docId: `share_promo_reward_${referralId}`,
          title: notificationTitle,
          body: notificationBody,
          userUid: referral.inviterUid,
        }),
        notifyInviterRewardByEmail(
          referral.inviterUid,
          notificationTitle,
          notificationBody,
        ).catch((error) => {
          console.log(
            `[share_promo] reward email failed referralId=${referralId} uid=${referral.inviterUid} error=${error}`,
          );
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
    const bonusExpiresAt =
      toTimestamp(userData.bonusExpiresAt) ?? toTimestamp(userData.allGamesAccessUntil);
    const bonusMode = normalizeString(userData.bonusMode);
    const bonusSource = normalizeString(userData.bonusSource);
    const bonusActive =
      bonusExpiresAt != null && bonusExpiresAt.toMillis() > Date.now();

    let kind: string | null = null;
    let title: string | null = null;
    let message: string | null = null;
    let action: string | null = null;
    let playerStatus: string | null = null;

    if (bonusActive) {
      kind = 'bonusActive';
      title = 'Bonus activ?';
      message = 'Vous pouvez jouer ? tous les jeux jusqu?? minuit.';
      action = 'bonusActive';
      playerStatus = 'bonus_active';
    } else if (shareState.rewardAvailable) {
      kind = 'rewardAvailable';
      title = 'R?compense disponible';
      message = 'Votre bonus de parrainage est disponible.';
      action = 'rewardAvailable';
      playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    } else if (shareState.pendingCount > 0) {
      kind = 'friendPending';
      title = 'Invitation en attente';
      message = 'Un ami n?a pas encore finalis? son inscription.';
      action = 'friendPending';
      playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    } else if (campaignActive && campaign.kind !== 'defaultInvite') {
      kind = 'specialCampaign';
      title = campaign.title;
      message = campaign.message;
      action = 'specialCampaign';
      playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    } else if (campaignActive && remainingPart <= 1) {
      kind = 'lowRemainingPlaysInvite';
      title = remainingPart <= 0
          ? 'Plus de chances disponibles'
          : 'Plus qu?une chance disponible';
      message = 'Invitez un proche pour continuer ? jouer.';
      action = 'lowRemainingPlaysInvite';
      playerStatus = remainingPart <= 0 ? 'no_parts' : 'low_parts';
    } else if (campaignActive) {
      kind = 'defaultInvite';
      title = campaign.title;
      message = campaign.message;
      action = 'defaultInvite';
      playerStatus = 'normal';
    } else {
      playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    }

    return {
      showBanner: kind != null,
      kind,
      title,
      message,
      ctaText: kind == null ? null : campaign.ctaText,
      action,
      playerStatus,
      bonusMode: bonusMode || null,
      bonusSource: bonusSource || null,
      bonusExpiresAt,
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

export const validateReferralCode = functions
  .region(region)
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(
    async (
      data: ValidateReferralCodeInput,
      _context,
    ): Promise<ValidateReferralCodeResponse> => {
      const inviteCode = normalizeString(data?.inviteCode).toUpperCase();
      if (!inviteCode) {
        return {
          valid: false,
          inviteCode: '',
          reason: 'empty',
        };
      }

      const referralQuery = await refs
        .referrals()
        .where('inviteCode', '==', inviteCode)
        .limit(1)
        .get();

      if (referralQuery.empty) {
        const legacyUserQuery = await db
          .collection('users')
          .where('referralCode', '==', inviteCode)
          .limit(1)
          .get();

        return {
          valid: !legacyUserQuery.empty,
          inviteCode,
          reason: legacyUserQuery.empty ? 'not_found' : 'legacy_user',
        };
      }

      const referral = referralQuery.docs[0].data() as ReferralRecord;
      const isPending = referral.status === 'pending' && !referral.inviteeUid;
      return {
        valid: isPending,
        inviteCode,
        reason: isPending ? null : 'already_used',
      };
    },
  );

export const registerReferralAcceptance = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = normalizeString(data?.inviteCode).toUpperCase();
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
    const referralRef = referralQuery.empty
      ? refs.referrals().doc()
      : referralQuery.docs[0].ref;
    const legacyInviterRef = referralQuery.empty
      ? (
          await db
            .collection('users')
            .where('referralCode', '==', inviteCode)
            .limit(1)
            .get()
        ).docs[0]?.ref ?? null
      : null;

    if (referralQuery.empty && !legacyInviterRef) {
      throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }

    const campaign = await loadCampaign();
    const acceptanceResult = await db.runTransaction(async (transaction) => {
      const asyncReads: Array<Promise<FirebaseFirestore.DocumentSnapshot | FirebaseFirestore.QuerySnapshot>> = [
        transaction.get(refs.user(auth.uid)),
        transaction.get(refs.referrals().where('inviteeUid', '==', auth.uid).limit(1)),
      ];

      if (referralQuery.empty) {
        asyncReads.unshift(transaction.get(legacyInviterRef!));
      } else {
        asyncReads.unshift(transaction.get(referralRef));
      }

      const [primarySnap, inviteeUserSnap, existingInviteeReferralSnap] =
        await Promise.all(asyncReads) as [
          FirebaseFirestore.DocumentSnapshot,
          FirebaseFirestore.DocumentSnapshot,
          FirebaseFirestore.QuerySnapshot,
        ];

      let inviterUid: string;
      if (referralQuery.empty) {
        if (!primarySnap.exists) {
          throw new functions.https.HttpsError('not-found', 'Referral not found.');
        }
        inviterUid = primarySnap.id;
      } else {
        const referral = primarySnap.data() as ReferralRecord;
        inviterUid = referral.inviterUid;
        if (referral.status !== 'pending' || referral.inviteeUid) {
          throw new functions.https.HttpsError(
            'already-exists',
            'This referral has already been accepted.',
          );
        }
      }

      if (inviterUid === auth.uid) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Self-referrals are not allowed.',
        );
      }
      if (!(existingInviteeReferralSnap as FirebaseFirestore.QuerySnapshot).empty) {
        throw new functions.https.HttpsError(
          'already-exists',
          'A referral has already been used for this account.',
        );
      }

      const rewardStatus =
        campaign.requireInviteeSignup && !inviteeUserSnap.exists
          ? 'blocked'
          : 'available';

      if (referralQuery.empty) {
        const inviterData = primarySnap.data() ?? {};
        const inviterPseudo =
          normalizeNullableString(inviterData.pseudo) ??
          normalizeNullableString(inviterData.display_name) ??
          normalizeNullableString(inviterData.first_name);

        const referral: ReferralRecord = {
          campaignId,
          inviterUid,
          inviterPseudo,
          inviteeUid: auth.uid,
          inviteeContact: null,
          inviteCode,
          shareChannel: 'legacy_referral_code',
          status: 'accepted',
          rewardStatus,
          rewardType: campaign.rewardType,
          rewardValue: campaign.rewardValue,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          acceptedAt: admin.firestore.Timestamp.now(),
          rewardGrantedAt: null,
          expiredAt: null,
          createdFromDeviceId: null,
          acceptedFromDeviceId: normalizeNullableString(
            data?.acceptedFromDeviceId,
          ),
          metadata: {
            legacyReferralCode: true,
          },
        };
        transaction.set(referralRef, referral);
      } else {
        transaction.update(referralRef, {
          inviteeUid: auth.uid,
          status: 'accepted',
          acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
          acceptedFromDeviceId: normalizeNullableString(
            data?.acceptedFromDeviceId,
          ),
          rewardStatus,
        });
      }
      return { inviterUid, rewardStatus };
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


export const adminGetNotificationsConfig = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (_data, context) => {
    await requireAdmin(context);
    return loadNotificationsConfig();
  });

export const adminSetNotificationsConfig = functions
  .region(region)
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    const adminUid = await requireAdmin(context);
    const dailyRemainingChancesReminderEnabled =
      data?.dailyRemainingChancesReminderEnabled !== false;

    await db.collection('app_config').doc('notifications').set(
      {
        dailyRemainingChancesReminderEnabled,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: refs.user(adminUid),
      },
      { merge: true },
    );

    return {
      ok: true,
      dailyRemainingChancesReminderEnabled,
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

export const remindUsersWithRemainingDailyPlays = functions
  .region(region)
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 18 * * *')
  .timeZone('Europe/Paris')
  .onRun(async () => {
    const { dailyRemainingChancesReminderEnabled } =
      await loadNotificationsConfig();
    if (!dailyRemainingChancesReminderEnabled) {
      console.log(
        '[remindUsersWithRemainingDailyPlays] skipped dailyRemainingChancesReminderEnabled=false',
      );
      return null;
    }

    const dateKey = getParisDateKey();
    const usersSnap = await db
      .collection('users')
      .where('remaining_part', '>', 0)
      .get();

    let queued = 0;
    let skippedAlreadyQueued = 0;
    let skippedWithoutParts = 0;
    let failed = 0;

    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data() ?? {};
      const remainingPart = normalizeNumber(userData.remaining_part, 0);
      if (remainingPart <= 0) {
        skippedWithoutParts += 1;
        continue;
      }

      const notificationDocId = `daily_remaining_plays_${dateKey}_${userDoc.id}`;
      const notificationRef = db
        .collection(pushNotificationsCollection)
        .doc(notificationDocId);
      const notificationSnap = await notificationRef.get();
      if (notificationSnap.exists) {
        skippedAlreadyQueued += 1;
        continue;
      }

      try {
        const shareStateSnap = await refs.shareState(userDoc.id).get();
        const shareState = shareStateSnap.exists ? shareStateSnap.data() ?? {} : {};
        const lastIndex = parseDailyReminderIndex(
          shareState.lastDailyPlayReminderIndex,
        );
        const variant = pickDailyPlaysReminderVariant(lastIndex);

        await queueUserPushNotification({
          docId: notificationDocId,
          title: variant.title,
          body: variant.body,
          userUid: userDoc.id,
          createdBy: 'system/remindUsersWithRemainingDailyPlays',
        });

        await refs.shareState(userDoc.id).set(
          {
            lastDailyPlayReminderDateKey: dateKey,
            lastDailyPlayReminderIndex: variant.index,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        queued += 1;
      } catch (error) {
        failed += 1;
        console.log(
          `[remindUsersWithRemainingDailyPlays] user=${userDoc.id} error=${error}`,
        );
      }
    }

    console.log(
      '[remindUsersWithRemainingDailyPlays] done',
      JSON.stringify({
        dateKey,
        matchedUsers: usersSnap.size,
        queued,
        skippedAlreadyQueued,
        skippedWithoutParts,
        failed,
      }),
    );

    return null;
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
