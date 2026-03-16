import * as admin from 'firebase-admin';
import { randomBytes } from 'crypto';
import {
  AdminStatsRecord,
  RewardEventRecord,
  SharePromoConfig,
  ShareStateRecord,
} from './types';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

export const db = admin.firestore();
export const region = 'us-central1';
export const campaignId = 'share_promo';
export const defaultReferralExpirationDays = 14;
export const rewardAccessTimeZone = 'Europe/Paris';
export const pushNotificationsCollection = 'ff_push_notifications';
export const sharePromoOneLinkBase = 'https://onelink.to/jx4ee7';

// Firestore doc paths must have an even number of segments.
export const paths = {
  sharePromoConfig: 'app_config/share_promo',
  adminStats: 'admin_stats/share_promo',
  shareState: (uid: string) => `users/${uid}/private/share_state`,
  user: (uid: string) => `users/${uid}`,
  userNotification: (uid: string, notificationId: string) =>
    `users/${uid}/notifications/${notificationId}`,
  referral: (referralId: string) => `referrals/${referralId}`,
  rewardEvent: (eventId: string) => `reward_events/${eventId}`,
};

export const refs = {
  sharePromoConfig: () => db.doc(paths.sharePromoConfig),
  adminStats: () => db.doc(paths.adminStats),
  shareState: (uid: string) => db.doc(paths.shareState(uid)),
  user: (uid: string) => db.doc(paths.user(uid)),
  userNotification: (uid: string, notificationId: string) =>
    db.doc(paths.userNotification(uid, notificationId)),
  referral: (referralId: string) => db.doc(paths.referral(referralId)),
  rewardEvent: (eventId: string) => db.doc(paths.rewardEvent(eventId)),
  referrals: () => db.collection('referrals'),
  rewardEvents: () => db.collection('reward_events'),
};

export const defaultSharePromoConfig: SharePromoConfig = {
  enabled: false,
  kind: 'defaultInvite',
  title: 'Invitez vos proches',
  message: 'Partagez Proxiplay avec vos amis et gagnez des bonus.',
  ctaText: 'Partager',
  startAt: null,
  endAt: null,
  rewardType: 'all_games_until_midnight',
  rewardValue: 1,
  maxRewardsPerUser: 10,
  maxRewardsPerInvitee: 1,
  requireInviteeSignup: true,
  audience: 'all',
  isDraft: true,
  priority: 0,
  updatedBy: 'system',
};

export const defaultShareState: ShareStateRecord = {
  pendingCount: 0,
  acceptedCount: 0,
  grantedCount: 0,
  rewardAvailable: false,
  lastReferralAt: null,
  lastRewardAt: null,
  lastDailyPlayReminderDateKey: null,
  lastDailyPlayReminderIndex: null,
  remainingEligibleRewards: 0,
  currentBannerKind: null,
  currentBannerTitle: null,
  currentBannerMessage: null,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};

export const defaultAdminStats: AdminStatsRecord = {
  pendingReferrals: 0,
  acceptedReferrals: 0,
  grantedRewards: 0,
  activeCampaigns: 0,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};

export function normalizeString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

export function normalizeNullableString(value: unknown): string | null {
  const normalized = normalizeString(value);
  return normalized.length > 0 ? normalized : null;
}

export function normalizeNumber(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', '1', 'yes', 'on'].includes(normalized)) {
      return true;
    }
    if (['false', '0', 'no', 'off'].includes(normalized)) {
      return false;
    }
  }
  return fallback;
}

export function toTimestamp(
  value: unknown,
): admin.firestore.Timestamp | null {
  if (value == null) {
    return null;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }
  if (
    typeof value === 'object' &&
    value !== null &&
    'seconds' in value &&
    typeof (value as { seconds: unknown }).seconds === 'number'
  ) {
    const casted = value as { seconds: number; nanoseconds?: number };
    return new admin.firestore.Timestamp(
      casted.seconds,
      casted.nanoseconds ?? 0,
    );
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return admin.firestore.Timestamp.fromMillis(value);
  }
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    if (!Number.isNaN(ms)) {
      return admin.firestore.Timestamp.fromMillis(ms);
    }
  }
  return null;
}

export function buildActiveCampaign(
  raw: Partial<SharePromoConfig> | undefined,
): SharePromoConfig {
  return {
    ...defaultSharePromoConfig,
    ...(raw ?? {}),
    enabled: normalizeBoolean(raw?.enabled, defaultSharePromoConfig.enabled),
    kind: normalizeString(raw?.kind) || defaultSharePromoConfig.kind,
    title: normalizeString(raw?.title) || defaultSharePromoConfig.title,
    message: normalizeString(raw?.message) || defaultSharePromoConfig.message,
    ctaText: normalizeString(raw?.ctaText) || defaultSharePromoConfig.ctaText,
    startAt: toTimestamp(raw?.startAt),
    endAt: toTimestamp(raw?.endAt),
    rewardType:
      normalizeString(raw?.rewardType) || defaultSharePromoConfig.rewardType,
    rewardValue: normalizeNumber(
      raw?.rewardValue,
      defaultSharePromoConfig.rewardValue,
    ),
    maxRewardsPerUser: normalizeNumber(
      raw?.maxRewardsPerUser,
      defaultSharePromoConfig.maxRewardsPerUser,
    ),
    maxRewardsPerInvitee: normalizeNumber(
      raw?.maxRewardsPerInvitee,
      defaultSharePromoConfig.maxRewardsPerInvitee,
    ),
    requireInviteeSignup: normalizeBoolean(
      raw?.requireInviteeSignup,
      defaultSharePromoConfig.requireInviteeSignup,
    ),
    audience:
      normalizeString(raw?.audience) || defaultSharePromoConfig.audience,
    isDraft: normalizeBoolean(raw?.isDraft, defaultSharePromoConfig.isDraft),
    priority: normalizeNumber(raw?.priority, defaultSharePromoConfig.priority),
    updatedBy:
      normalizeString(raw?.updatedBy) || defaultSharePromoConfig.updatedBy,
  };
}

export function isCampaignActive(
  config: SharePromoConfig,
  now = admin.firestore.Timestamp.now(),
): boolean {
  if (!config.enabled || config.isDraft) {
    return false;
  }
  if (config.startAt && config.startAt.toMillis() > now.toMillis()) {
    return false;
  }
  if (config.endAt && config.endAt.toMillis() < now.toMillis()) {
    return false;
  }
  return true;
}

export async function generateUniqueInviteCode(): Promise<string> {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const candidate = randomBytes(4).toString('hex').toUpperCase();
    const existing = await refs
      .referrals()
      .where('inviteCode', '==', candidate)
      .limit(1)
      .get();
    if (existing.empty) {
      return candidate;
    }
  }
  throw new Error('Unable to generate a unique invite code.');
}

export function buildShareLink(inviteCode: string): string {
  const baseUri = new URL(sharePromoOneLinkBase);
  baseUri.searchParams.set('ref', inviteCode);
  return baseUri.toString();
}

export function buildShareMessage(
  config: SharePromoConfig,
  inviteCode: string,
): string {
  return config.message
    .replace(/\{code\}/g, inviteCode)
    .replace(/\{rewardValue\}/g, String(config.rewardValue));
}

export async function recomputeAdminStats(): Promise<AdminStatsRecord> {
  const [pendingSnap, acceptedSnap, grantedSnap, campaignSnap] =
    await Promise.all([
      refs.referrals().where('status', '==', 'pending').count().get(),
      refs.referrals().where('status', '==', 'accepted').count().get(),
      refs.referrals().where('rewardStatus', '==', 'granted').count().get(),
      refs.sharePromoConfig().get(),
    ]);

  const config = buildActiveCampaign(
    (campaignSnap.exists ? campaignSnap.data() : undefined) as
      | Partial<SharePromoConfig>
      | undefined,
  );

  const stats: AdminStatsRecord = {
    pendingReferrals: pendingSnap.data().count,
    acceptedReferrals: acceptedSnap.data().count,
    grantedRewards: grantedSnap.data().count,
    activeCampaigns: isCampaignActive(config) ? 1 : 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await refs.adminStats().set(stats, { merge: true });
  return stats;
}

export async function recomputeShareState(
  uid: string,
): Promise<ShareStateRecord> {
  const [campaignSnap, pendingSnap, acceptedSnap, availableSnap, grantedSnap] =
    await Promise.all([
      refs.sharePromoConfig().get(),
      refs
        .referrals()
        .where('inviterUid', '==', uid)
        .where('status', '==', 'pending')
        .count()
        .get(),
      refs
        .referrals()
        .where('inviterUid', '==', uid)
        .where('status', '==', 'accepted')
        .count()
        .get(),
      refs
        .referrals()
        .where('inviterUid', '==', uid)
        .where('rewardStatus', '==', 'available')
        .count()
        .get(),
      refs
        .referrals()
        .where('inviterUid', '==', uid)
        .where('rewardStatus', '==', 'granted')
        .count()
        .get(),
    ]);

  const [lastReferralSnap, lastRewardSnap] = await Promise.all([
    refs
      .referrals()
      .where('inviterUid', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(1)
      .get(),
    refs
      .rewardEvents()
      .where('uid', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(1)
      .get(),
  ]);

  const config = buildActiveCampaign(
    (campaignSnap.exists ? campaignSnap.data() : undefined) as
      | Partial<SharePromoConfig>
      | undefined,
  );
  const grantedCount = grantedSnap.data().count;
  const pendingCount = pendingSnap.data().count;
  const availableCount = availableSnap.data().count;

  const state: ShareStateRecord = {
    pendingCount,
    acceptedCount: acceptedSnap.data().count,
    grantedCount,
    rewardAvailable: availableCount > 0,
    lastReferralAt: lastReferralSnap.empty
        ? null
        : ((lastReferralSnap.docs[0].get('createdAt') as
            admin.firestore.Timestamp | null) ?? null),
    lastRewardAt: lastRewardSnap.empty
        ? null
        : ((lastRewardSnap.docs[0].get('createdAt') as
            admin.firestore.Timestamp | null) ?? null),
    remainingEligibleRewards: Math.max(
      0,
      config.maxRewardsPerUser - grantedCount,
    ),
    currentBannerKind: availableCount > 0
        ? 'rewardAvailable'
        : pendingCount > 0
        ? 'friendPending'
        : isCampaignActive(config)
        ? config.kind
        : 'defaultInvite',
    currentBannerTitle: availableCount > 0
        ? 'Recompense disponible'
        : pendingCount > 0
        ? 'Invitation en attente'
        : config.title,
    currentBannerMessage: availableCount > 0
        ? 'Votre bonus de parrainage est disponible.'
        : pendingCount > 0
        ? 'Une invitation est en attente de validation.'
        : config.message,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await refs.shareState(uid).set(state, { merge: true });
  return state;
}

export function isRewardPlayable(type: string): boolean {
  return ['play_credit', 'plays', 'remaining_part', 'game_bonus'].includes(
    normalizeString(type),
  );
}

function parseTimeZoneOffsetMs(value: string): number {
  const normalized = value.replace('GMT', '');
  const match = normalized.match(/^([+-])(\d{1,2})(?::?(\d{2}))?$/);
  if (!match) {
    return 0;
  }
  const sign = match[1] === '-' ? -1 : 1;
  const hours = Number(match[2] ?? '0');
  const minutes = Number(match[3] ?? '0');
  return sign * (hours * 60 + minutes) * 60 * 1000;
}

function getTimeZoneOffsetMs(date: Date, timeZone: string): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    timeZoneName: 'shortOffset',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(date);
  const offset = parts.find((part) => part.type === 'timeZoneName')?.value;
  return offset ? parseTimeZoneOffsetMs(offset) : 0;
}

function getDatePartsInTimeZone(
  date: Date,
  timeZone: string,
): { year: number; month: number; day: number } {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const parts = formatter.formatToParts(date);
  return {
    year: Number(parts.find((part) => part.type === 'year')?.value ?? '1970'),
    month: Number(parts.find((part) => part.type === 'month')?.value ?? '1'),
    day: Number(parts.find((part) => part.type === 'day')?.value ?? '1'),
  };
}

function buildTimeZoneMidnightTimestamp(
  year: number,
  month: number,
  day: number,
  timeZone: string,
): admin.firestore.Timestamp {
  const utcGuess = Date.UTC(year, month - 1, day, 0, 0, 0, 0);
  const offsetMs = getTimeZoneOffsetMs(new Date(utcGuess), timeZone);
  return admin.firestore.Timestamp.fromMillis(utcGuess - offsetMs);
}

export function getNextMidnightTimestamp(
  now = admin.firestore.Timestamp.now(),
  timeZone = rewardAccessTimeZone,
): admin.firestore.Timestamp {
  const localDate = getDatePartsInTimeZone(now.toDate(), timeZone);
  const nextDayUtc = new Date(
    Date.UTC(localDate.year, localDate.month - 1, localDate.day + 1),
  );
  return buildTimeZoneMidnightTimestamp(
    nextDayUtc.getUTCFullYear(),
    nextDayUtc.getUTCMonth() + 1,
    nextDayUtc.getUTCDate(),
    timeZone,
  );
}

export function isAllGamesUntilMidnightReward(type: string): boolean {
  return normalizeString(type) === 'all_games_until_midnight';
}

export async function applyRewardToUser(
  transaction: admin.firestore.Transaction,
  uid: string,
  rewardType: string,
  rewardValue: number,
): Promise<void> {
  if (isAllGamesUntilMidnightReward(rewardType)) {
    const userRef = refs.user(uid);
    const userSnap = await transaction.get(userRef);
    const userData = userSnap.data() ?? {};
    const nextMidnight = getNextMidnightTimestamp();
    const existingBonusExpiry =
      toTimestamp(userData.bonusExpiresAt) ?? toTimestamp(userData.allGamesAccessUntil);
    const effectiveBonusExpiry =
      existingBonusExpiry && existingBonusExpiry.toMillis() > nextMidnight.toMillis()
        ? existingBonusExpiry
        : nextMidnight;

    transaction.set(
      userRef,
      {
        allGamesAccessUntil: effectiveBonusExpiry,
        bonusMode: 'all_games_until_midnight',
        bonusExpiresAt: effectiveBonusExpiry,
        bonusSource: 'referral',
        updated_time: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  if (!isRewardPlayable(rewardType) || rewardValue <= 0) {
    return;
  }

  transaction.set(
    refs.user(uid),
    {
      remaining_part: admin.firestore.FieldValue.increment(rewardValue),
      updated_time: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export function buildRewardEvent(
  uid: string,
  referralId: string,
  config: SharePromoConfig,
  grantedBy: string,
): RewardEventRecord {
  return {
    uid,
    referralId,
    campaignId,
    type: config.rewardType,
    value: config.rewardValue,
    status: 'granted',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    grantedBy,
  };
}

export async function queueUserPushNotification({
  docId,
  title,
  body,
  userUid,
  createdBy,
}: {
  docId: string;
  title: string;
  body: string;
  userUid: string;
  createdBy: string;
}): Promise<void> {
  const ref = db.collection(pushNotificationsCollection).doc(docId);
  const existing = await ref.get();
  if (existing.exists) {
    return;
  }

  await ref.set({
    notification_title: title,
    notification_text: body,
    notification_image_url: '',
    notification_sound: '',
    parameter_data: '',
    initial_page_name: '',
    target_audience: 'All',
    target_user_group: 'All',
    user_refs: paths.user(userUid),
    status: 'started',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy,
  });
}


export async function createUserInAppNotification({
  docId,
  title,
  body,
  userUid,
}: {
  docId: string;
  title: string;
  body: string;
  userUid: string;
}): Promise<void> {
  const ref = refs.userNotification(userUid, docId);
  const existing = await ref.get();
  if (existing.exists) {
    return;
  }

  await ref.set({
    title,
    message: body,
    date: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });
}
