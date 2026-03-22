"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.defaultAdminStats = exports.defaultShareState = exports.defaultSharePromoConfig = exports.refs = exports.paths = exports.sharePromoOneLinkBase = exports.pushNotificationsCollection = exports.rewardAccessTimeZone = exports.defaultReferralExpirationDays = exports.campaignId = exports.region = exports.db = void 0;
exports.normalizeString = normalizeString;
exports.normalizeNullableString = normalizeNullableString;
exports.normalizeNumber = normalizeNumber;
exports.normalizeBoolean = normalizeBoolean;
exports.toTimestamp = toTimestamp;
exports.buildActiveCampaign = buildActiveCampaign;
exports.isCampaignActive = isCampaignActive;
exports.generateUniqueInviteCode = generateUniqueInviteCode;
exports.buildShareLink = buildShareLink;
exports.buildShareMessage = buildShareMessage;
exports.recomputeAdminStats = recomputeAdminStats;
exports.recomputeShareState = recomputeShareState;
exports.isRewardPlayable = isRewardPlayable;
exports.getCurrentDayEndTimestamp = getCurrentDayEndTimestamp;
exports.isAllGamesUntilMidnightReward = isAllGamesUntilMidnightReward;
exports.applyRewardToUser = applyRewardToUser;
exports.buildRewardEvent = buildRewardEvent;
exports.queueUserPushNotification = queueUserPushNotification;
exports.createUserInAppNotification = createUserInAppNotification;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
if (admin.apps.length === 0) {
    admin.initializeApp();
}
exports.db = admin.firestore();
exports.region = 'us-central1';
exports.campaignId = 'share_promo';
exports.defaultReferralExpirationDays = 14;
exports.rewardAccessTimeZone = 'Europe/Paris';
exports.pushNotificationsCollection = 'ff_push_notifications';
exports.sharePromoOneLinkBase = 'https://onelink.to/jx4ee7';
// Firestore doc paths must have an even number of segments.
exports.paths = {
    sharePromoConfig: 'app_config/share_promo',
    adminStats: 'admin_stats/share_promo',
    shareState: (uid) => `users/${uid}/private/share_state`,
    user: (uid) => `users/${uid}`,
    userNotification: (uid, notificationId) => `users/${uid}/notifications/${notificationId}`,
    referral: (referralId) => `referrals/${referralId}`,
    rewardEvent: (eventId) => `reward_events/${eventId}`,
};
exports.refs = {
    sharePromoConfig: () => exports.db.doc(exports.paths.sharePromoConfig),
    adminStats: () => exports.db.doc(exports.paths.adminStats),
    shareState: (uid) => exports.db.doc(exports.paths.shareState(uid)),
    user: (uid) => exports.db.doc(exports.paths.user(uid)),
    userNotification: (uid, notificationId) => exports.db.doc(exports.paths.userNotification(uid, notificationId)),
    referral: (referralId) => exports.db.doc(exports.paths.referral(referralId)),
    rewardEvent: (eventId) => exports.db.doc(exports.paths.rewardEvent(eventId)),
    referrals: () => exports.db.collection('referrals'),
    rewardEvents: () => exports.db.collection('reward_events'),
};
exports.defaultSharePromoConfig = {
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
exports.defaultShareState = {
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
exports.defaultAdminStats = {
    pendingReferrals: 0,
    acceptedReferrals: 0,
    grantedRewards: 0,
    activeCampaigns: 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};
function normalizeString(value) {
    return typeof value === 'string' ? value.trim() : '';
}
function normalizeNullableString(value) {
    const normalized = normalizeString(value);
    return normalized.length > 0 ? normalized : null;
}
function normalizeNumber(value, fallback = 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}
function normalizeBoolean(value, fallback = false) {
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
function toTimestamp(value) {
    if (value == null) {
        return null;
    }
    if (value instanceof admin.firestore.Timestamp) {
        return value;
    }
    if (typeof value === 'object' &&
        value !== null &&
        'seconds' in value &&
        typeof value.seconds === 'number') {
        const casted = value;
        return new admin.firestore.Timestamp(casted.seconds, casted.nanoseconds ?? 0);
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
function buildActiveCampaign(raw) {
    return {
        ...exports.defaultSharePromoConfig,
        ...(raw ?? {}),
        enabled: normalizeBoolean(raw?.enabled, exports.defaultSharePromoConfig.enabled),
        kind: normalizeString(raw?.kind) || exports.defaultSharePromoConfig.kind,
        title: normalizeString(raw?.title) || exports.defaultSharePromoConfig.title,
        message: normalizeString(raw?.message) || exports.defaultSharePromoConfig.message,
        ctaText: normalizeString(raw?.ctaText) || exports.defaultSharePromoConfig.ctaText,
        startAt: toTimestamp(raw?.startAt),
        endAt: toTimestamp(raw?.endAt),
        rewardType: normalizeString(raw?.rewardType) || exports.defaultSharePromoConfig.rewardType,
        rewardValue: normalizeNumber(raw?.rewardValue, exports.defaultSharePromoConfig.rewardValue),
        maxRewardsPerUser: normalizeNumber(raw?.maxRewardsPerUser, exports.defaultSharePromoConfig.maxRewardsPerUser),
        maxRewardsPerInvitee: normalizeNumber(raw?.maxRewardsPerInvitee, exports.defaultSharePromoConfig.maxRewardsPerInvitee),
        requireInviteeSignup: normalizeBoolean(raw?.requireInviteeSignup, exports.defaultSharePromoConfig.requireInviteeSignup),
        audience: normalizeString(raw?.audience) || exports.defaultSharePromoConfig.audience,
        isDraft: normalizeBoolean(raw?.isDraft, exports.defaultSharePromoConfig.isDraft),
        priority: normalizeNumber(raw?.priority, exports.defaultSharePromoConfig.priority),
        updatedBy: normalizeString(raw?.updatedBy) || exports.defaultSharePromoConfig.updatedBy,
    };
}
function isCampaignActive(config, now = admin.firestore.Timestamp.now()) {
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
async function generateUniqueInviteCode() {
    for (let attempt = 0; attempt < 8; attempt += 1) {
        const candidate = (0, crypto_1.randomBytes)(4).toString('hex').toUpperCase();
        const existing = await exports.refs
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
function buildShareLink(inviteCode) {
    const baseUri = new URL(exports.sharePromoOneLinkBase);
    baseUri.searchParams.set('ref', inviteCode);
    return baseUri.toString();
}
function buildShareMessage(config, inviteCode) {
    return config.message
        .replace(/\{code\}/g, inviteCode)
        .replace(/\{rewardValue\}/g, String(config.rewardValue));
}
async function recomputeAdminStats() {
    const [pendingSnap, acceptedSnap, grantedSnap, campaignSnap] = await Promise.all([
        exports.refs.referrals().where('status', '==', 'pending').count().get(),
        exports.refs.referrals().where('status', '==', 'accepted').count().get(),
        exports.refs.referrals().where('rewardStatus', '==', 'granted').count().get(),
        exports.refs.sharePromoConfig().get(),
    ]);
    const config = buildActiveCampaign((campaignSnap.exists ? campaignSnap.data() : undefined));
    const stats = {
        pendingReferrals: pendingSnap.data().count,
        acceptedReferrals: acceptedSnap.data().count,
        grantedRewards: grantedSnap.data().count,
        activeCampaigns: isCampaignActive(config) ? 1 : 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await exports.refs.adminStats().set(stats, { merge: true });
    return stats;
}
async function recomputeShareState(uid) {
    const [campaignSnap, pendingSnap, acceptedSnap, availableSnap, grantedSnap] = await Promise.all([
        exports.refs.sharePromoConfig().get(),
        exports.refs
            .referrals()
            .where('inviterUid', '==', uid)
            .where('status', '==', 'pending')
            .count()
            .get(),
        exports.refs
            .referrals()
            .where('inviterUid', '==', uid)
            .where('status', '==', 'accepted')
            .count()
            .get(),
        exports.refs
            .referrals()
            .where('inviterUid', '==', uid)
            .where('rewardStatus', '==', 'available')
            .count()
            .get(),
        exports.refs
            .referrals()
            .where('inviterUid', '==', uid)
            .where('rewardStatus', '==', 'granted')
            .count()
            .get(),
    ]);
    const [lastReferralSnap, lastRewardSnap] = await Promise.all([
        exports.refs
            .referrals()
            .where('inviterUid', '==', uid)
            .orderBy('createdAt', 'desc')
            .limit(1)
            .get(),
        exports.refs
            .rewardEvents()
            .where('uid', '==', uid)
            .orderBy('createdAt', 'desc')
            .limit(1)
            .get(),
    ]);
    const config = buildActiveCampaign((campaignSnap.exists ? campaignSnap.data() : undefined));
    const grantedCount = grantedSnap.data().count;
    const pendingCount = pendingSnap.data().count;
    const availableCount = availableSnap.data().count;
    const state = {
        pendingCount,
        acceptedCount: acceptedSnap.data().count,
        grantedCount,
        rewardAvailable: availableCount > 0,
        lastReferralAt: lastReferralSnap.empty
            ? null
            : (lastReferralSnap.docs[0].get('createdAt') ?? null),
        lastRewardAt: lastRewardSnap.empty
            ? null
            : (lastRewardSnap.docs[0].get('createdAt') ?? null),
        remainingEligibleRewards: Math.max(0, config.maxRewardsPerUser - grantedCount),
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
    await exports.refs.shareState(uid).set(state, { merge: true });
    return state;
}
function isRewardPlayable(type) {
    return ['play_credit', 'plays', 'remaining_part', 'game_bonus'].includes(normalizeString(type));
}
function parseTimeZoneOffsetMs(value) {
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
function getTimeZoneOffsetMs(date, timeZone) {
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
function getDatePartsInTimeZone(date, timeZone) {
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
function buildTimeZoneMidnightTimestamp(year, month, day, timeZone) {
    const utcGuess = Date.UTC(year, month - 1, day, 0, 0, 0, 0);
    const offsetMs = getTimeZoneOffsetMs(new Date(utcGuess), timeZone);
    return admin.firestore.Timestamp.fromMillis(utcGuess - offsetMs);
}
function getCurrentDayEndTimestamp(now = admin.firestore.Timestamp.now(), timeZone = exports.rewardAccessTimeZone) {
    const localDate = getDatePartsInTimeZone(now.toDate(), timeZone);
    const nextDayMidnight = buildTimeZoneMidnightTimestamp(localDate.year, localDate.month, localDate.day + 1, timeZone);
    return admin.firestore.Timestamp.fromMillis(nextDayMidnight.toMillis() - 1);
}
function isAllGamesUntilMidnightReward(type) {
    return normalizeString(type) === 'all_games_until_midnight';
}
async function applyRewardToUser(transaction, uid, rewardType, rewardValue, existingUserData) {
    if (isAllGamesUntilMidnightReward(rewardType)) {
        const userRef = exports.refs.user(uid);
        const userData = existingUserData ?? {};
        const currentDayEnd = getCurrentDayEndTimestamp();
        const existingBonusExpiry = toTimestamp(userData.bonusExpiresAt) ?? toTimestamp(userData.allGamesAccessUntil);
        const effectiveBonusExpiry = existingBonusExpiry && existingBonusExpiry.toMillis() > currentDayEnd.toMillis()
            ? existingBonusExpiry
            : currentDayEnd;
        transaction.set(userRef, {
            allGamesAccessUntil: effectiveBonusExpiry,
            bonusMode: 'all_games_until_midnight',
            bonusExpiresAt: effectiveBonusExpiry,
            bonusSource: 'referral',
            updated_time: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    if (!isRewardPlayable(rewardType) || rewardValue <= 0) {
        return;
    }
    transaction.set(exports.refs.user(uid), {
        remaining_part: admin.firestore.FieldValue.increment(rewardValue),
        updated_time: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
function buildRewardEvent(uid, referralId, config, grantedBy) {
    return {
        uid,
        referralId,
        campaignId: exports.campaignId,
        type: config.rewardType,
        value: config.rewardValue,
        status: 'granted',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        grantedBy,
    };
}
async function queueUserPushNotification({ docId, title, body, userUid, createdBy, }) {
    const ref = exports.db.collection(exports.pushNotificationsCollection).doc(docId);
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
        user_refs: exports.paths.user(userUid),
        status: 'started',
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        created_by: createdBy,
    });
}
async function createUserInAppNotification({ docId, title, body, userUid, }) {
    const ref = exports.refs.userNotification(userUid, docId);
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
