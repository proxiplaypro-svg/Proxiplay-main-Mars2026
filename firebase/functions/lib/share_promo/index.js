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
exports.adminGetSharePromoStats = exports.adminGetSharePromoConfig = exports.adminUpsertSharePromo = exports.expireOldReferrals = exports.remindUsersWithRemainingDailyPlays = exports.grantReferralReward = exports.adminSetNotificationsConfig = exports.adminGetNotificationsConfig = exports.registerReferralAcceptance = exports.validateReferralCode = exports.createReferral = exports.getSharePromoState = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const crypto = __importStar(require("crypto"));
const params_1 = require("firebase-functions/params");
const nodemailer = require('nodemailer');
const firestore_1 = require("./firestore");
const SMTP_HOST = (0, params_1.defineString)('SMTP_HOST');
const SMTP_PORT = (0, params_1.defineInt)('SMTP_PORT', { default: 587 });
const SMTP_SECURE = (0, params_1.defineBoolean)('SMTP_SECURE', { default: false });
const SMTP_USER = (0, params_1.defineString)('SMTP_USER');
const SMTP_PASS = (0, params_1.defineString)('SMTP_PASS');
const SMTP_FROM_EMAIL = (0, params_1.defineString)('SMTP_FROM_EMAIL');
const SMTP_FROM_NAME = (0, params_1.defineString)('SMTP_FROM_NAME');
const SMTP_REPLY_TO = (0, params_1.defineString)('SMTP_REPLY_TO', { default: '' });
const dailyPlaysReminderVariants = [
    {
        title: 'Il vous reste des chances !',
        body: 'Tentez votre chance avant minuit.',
    },
    {
        title: 'Vos parties du jour vous attendent',
        body: "Vous avez encore des chances \u00e0 jouer aujourd'hui.",
    },
    {
        title: 'Ne laissez pas vos parties expirer',
        body: 'Utilisez vos chances avant la fin de la journ\u00e9e.',
    },
    {
        title: 'Des jeux vous attendent encore',
        body: "Vous pouvez encore jouer sur ProxiPlay aujourd'hui.",
    },
    {
        title: 'Il est encore temps de jouer',
        body: 'Vos chances du jour ne sont pas encore utilis\u00e9es.',
    },
    {
        title: "Vous n'avez pas tout utilis\u00e9",
        body: 'Revenez tenter votre chance avant minuit.',
    },
    {
        title: 'Encore des chances disponibles',
        body: "Profitez-en tant qu'il est encore temps.",
    },
    {
        title: "Votre journ\u00e9e ProxiPlay n'est pas finie",
        body: 'Il vous reste encore des parties \u00e0 jouer.',
    },
];
function getParisDateKey(date = new Date()) {
    return new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Paris',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(date);
}
function parseDailyReminderIndex(value) {
    return Number.isInteger(value) ? Number(value) : null;
}
function pickDailyPlaysReminderVariant(lastIndex) {
    let index = Math.floor(Math.random() * dailyPlaysReminderVariants.length);
    if (dailyPlaysReminderVariants.length > 1 &&
        lastIndex !== null &&
        lastIndex >= 0 &&
        lastIndex < dailyPlaysReminderVariants.length &&
        index === lastIndex) {
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
function requireAuth(request) {
    const { auth } = request;
    if (!auth?.uid) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication is required.');
    }
    return auth;
}
async function requireAdmin(context) {
    const auth = requireAuth(context);
    if (auth.token.admin === true) {
        return auth.uid;
    }
    const userSnap = await firestore_1.refs.user(auth.uid).get();
    const userData = userSnap.data() ?? {};
    const userRole = (0, firestore_1.normalizeString)(userData.user_role) ||
        (0, firestore_1.normalizeString)(userData.userRole);
    if (userRole === 'admin') {
        return auth.uid;
    }
    throw new functions.https.HttpsError('permission-denied', 'Admin privileges are required.');
}
async function loadCampaign() {
    const campaignSnap = await firestore_1.refs.sharePromoConfig().get();
    return (0, firestore_1.buildActiveCampaign)((campaignSnap.exists ? campaignSnap.data() : undefined));
}
async function loadNotificationsConfig() {
    const configSnap = await firestore_1.db.collection('app_config').doc('notifications').get();
    const configData = (configSnap.data() ?? {});
    return {
        dailyRemainingChancesReminderEnabled: configData.dailyRemainingChancesReminderEnabled !== false,
    };
}
function getTrimmedString(value) {
    return typeof value == 'string' ? value.trim() : '';
}
function createSmtpMailer() {
    const host = getTrimmedString(SMTP_HOST.value());
    const port = Number(SMTP_PORT.value() || 587);
    const secure = SMTP_SECURE.value();
    const user = getTrimmedString(SMTP_USER.value());
    const pass = getTrimmedString(SMTP_PASS.value());
    const fromEmail = getTrimmedString(SMTP_FROM_EMAIL.value());
    const fromName = getTrimmedString(SMTP_FROM_NAME.value());
    const replyTo = getTrimmedString(SMTP_REPLY_TO.value());
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
        fromEmail,
        replyTo,
    };
}
function escapeHtml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
function linkifyHtml(text) {
    return escapeHtml(text).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" style="color:#0f766e;text-decoration:underline;">$1</a>');
}
function buildMessageId(fromEmail) {
    const domain = getTrimmedString(fromEmail).split('@')[1] || 'proxiplay.local';
    const uniqueId = typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : crypto.randomBytes(16).toString('hex');
    return `<${uniqueId}@${domain}>`;
}
function buildTransactionalEmailHtml(subject, text) {
    const content = getTrimmedString(text)
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((line) => `<p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1f2937;">${linkifyHtml(line)}</p>`)
        .join('');
    return ('<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:24px;background:#f4f7f5;font-family:Arial,sans-serif;color:#1f2937;">' +
        '<div style="max-width:640px;margin:0 auto;background:#ffffff;border:1px solid #dce7e2;border-radius:16px;overflow:hidden;">' +
        '<div style="padding:24px 28px;background:#0f766e;color:#ffffff;">' +
        `<div style="font-size:12px;letter-spacing:0.08em;text-transform:uppercase;opacity:0.9;">ProxiPlay</div><h1 style="margin:8px 0 0;font-size:24px;line-height:1.3;">${escapeHtml(subject)}</h1></div>` +
        `<div style="padding:28px;">${content}` +
        '<hr style="border:none;border-top:1px solid #e5e7eb;margin:24px 0;">' +
        '<p style="margin:0 0 8px;font-size:13px;line-height:1.6;color:#6b7280;">Email transactionnel envoye par ProxiPlay.</p>' +
        '<p style="margin:0;font-size:13px;line-height:1.6;color:#6b7280;">Site: <a href="https://proxiplay.fr" target="_blank" rel="noopener noreferrer" style="color:#0f766e;">proxiplay.fr</a><br>Contact: <a href="mailto:contact@proxiplay.fr" style="color:#0f766e;">contact@proxiplay.fr</a></p>' +
        '</div></div></body></html>');
}
async function resolveUserEmail(uid) {
    const userSnap = await firestore_1.refs.user(uid).get();
    const userData = userSnap.data() ?? {};
    const emailFromDoc = getTrimmedString(userData.email);
    if (emailFromDoc) {
        return emailFromDoc;
    }
    try {
        const authUser = await admin.auth().getUser(uid);
        return getTrimmedString(authUser.email);
    }
    catch (_) {
        return '';
    }
}
async function sendEmailNotification(mailer, to, subject, textBody) {
    const normalizedText = [
        getTrimmedString(textBody),
        '',
        '--',
        'ProxiPlay',
        'https://proxiplay.fr',
        'Contact : contact@proxiplay.fr',
    ].join('\n');
    await mailer.transporter.sendMail({
        from: mailer.from,
        sender: mailer.fromEmail,
        envelope: {
            from: mailer.fromEmail,
            to: [to],
        },
        to,
        subject,
        text: normalizedText,
        html: buildTransactionalEmailHtml(subject, normalizedText),
        messageId: buildMessageId(mailer.fromEmail),
        headers: {
            'X-Auto-Response-Suppress': 'OOF, AutoReply',
            'X-Transactional-Email': 'true',
        },
        ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
    });
}
async function writeRewardEmailAttempt(referralId, inviterUid, status, details = {}) {
    await firestore_1.db
        .collection('notifications')
        .doc(`share_promo_reward_email_${referralId}`)
        .set({
        type: 'share_promo_reward_email',
        referralId,
        inviterUid,
        status,
        details,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function notifyInviterRewardByEmail(referralId, inviterUid, subject, body) {
    const recipientEmail = await resolveUserEmail(inviterUid);
    if (!recipientEmail) {
        await writeRewardEmailAttempt(referralId, inviterUid, 'missing_email');
        console.log('[share_promo] reward email skipped: missing_email');
        return;
    }
    let mailer;
    try {
        mailer = createSmtpMailer();
        await mailer.transporter.verify();
    }
    catch (error) {
        await writeRewardEmailAttempt(referralId, inviterUid, 'smtp_unavailable', {
            error: String(error),
            to: recipientEmail,
        });
        console.log(`[share_promo] reward email skipped: smtp_unavailable error=${error}`);
        return;
    }
    await writeRewardEmailAttempt(referralId, inviterUid, 'sending', {
        to: recipientEmail,
        subject,
    });
    await sendEmailNotification(mailer, recipientEmail, subject, body);
    await writeRewardEmailAttempt(referralId, inviterUid, 'sent', {
        to: recipientEmail,
        subject,
    });
    console.log('[share_promo] reward email sent');
}
async function grantReferralRewardInternal(referralId, grantedBy) {
    const campaign = await loadCampaign();
    const referralRef = firestore_1.refs.referral(referralId);
    const eventRef = firestore_1.refs.rewardEvent(referralId);
    const result = await firestore_1.db.runTransaction(async (transaction) => {
        const referralSnap = await transaction.get(referralRef);
        if (!referralSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Referral not found.');
        }
        const referral = referralSnap.data();
        if (referral.rewardStatus === 'granted') {
            return { granted: false, reason: 'already_granted' };
        }
        if (referral.status !== 'accepted' || !referral.inviteeUid) {
            return { granted: false, reason: 'referral_not_eligible' };
        }
        const [inviterGrantedSnap, inviteeGrantedSnap, eventSnap, inviterUserSnap] = await Promise.all([
            transaction.get(firestore_1.refs
                .referrals()
                .where('inviterUid', '==', referral.inviterUid)
                .where('rewardStatus', '==', 'granted')),
            transaction.get(firestore_1.refs
                .referrals()
                .where('inviteeUid', '==', referral.inviteeUid)
                .where('rewardStatus', '==', 'granted')),
            transaction.get(eventRef),
            transaction.get(firestore_1.refs.user(referral.inviterUid)),
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
        transaction.set(eventRef, (0, firestore_1.buildRewardEvent)(referral.inviterUid, referralId, campaign, grantedBy));
        await (0, firestore_1.applyRewardToUser)(transaction, referral.inviterUid, referral.rewardType, referral.rewardValue, inviterUserSnap.data() ?? {});
        transaction.set(firestore_1.refs.shareState(referral.inviterUid), {
            grantedCount: admin.firestore.FieldValue.increment(1),
            rewardAvailable: false,
            lastRewardAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.update(referralRef, {
            rewardStatus: 'granted',
            rewardGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { granted: true };
    });
    if ('granted' in result && result.granted) {
        const referralSnap = await referralRef.get();
        const referral = referralSnap.data();
        const followUpTasks = [
            (0, firestore_1.recomputeShareState)(referral.inviterUid),
            (0, firestore_1.recomputeAdminStats)(),
        ];
        if ((0, firestore_1.isAllGamesUntilMidnightReward)(referral.rewardType)) {
            const notificationTitle = 'Bonne nouvelle !';
            const notificationBody = 'Votre parrainage a \u00e9t\u00e9 valid\u00e9. Vous pouvez jouer \u00e0 tous les jeux jusqu\u2019\u00e0 minuit.';
            followUpTasks.push((0, firestore_1.queueUserPushNotification)({
                docId: `share_promo_reward_${referralId}`,
                title: notificationTitle,
                body: notificationBody,
                userUid: referral.inviterUid,
                createdBy: grantedBy,
            }), (0, firestore_1.createUserInAppNotification)({
                docId: `share_promo_reward_${referralId}`,
                title: notificationTitle,
                body: notificationBody,
                userUid: referral.inviterUid,
            }), notifyInviterRewardByEmail(referralId, referral.inviterUid, notificationTitle, notificationBody).catch((error) => {
                void writeRewardEmailAttempt(referralId, referral.inviterUid, 'failed', {
                    error: String(error),
                });
                console.log(`[share_promo] reward email failed referralId=${referralId} error=${error}`);
            }));
        }
        await Promise.all(followUpTasks);
    }
    return result;
}
exports.getSharePromoState = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (_data, context) => {
    const auth = requireAuth(context);
    const [campaign, shareStateSnap, userSnap] = await Promise.all([
        loadCampaign(),
        firestore_1.refs.shareState(auth.uid).get(),
        firestore_1.refs.user(auth.uid).get(),
    ]);
    const userData = userSnap.data() ?? {};
    const shareState = shareStateSnap.exists
        ? { ...firestore_1.defaultShareState, ...shareStateSnap.data() }
        : firestore_1.defaultShareState;
    const remainingPart = (0, firestore_1.normalizeNumber)(userData.remaining_part, 0);
    const campaignActive = (0, firestore_1.isCampaignActive)(campaign);
    const bonusExpiresAt = (0, firestore_1.toTimestamp)(userData.bonusExpiresAt) ?? (0, firestore_1.toTimestamp)(userData.allGamesAccessUntil);
    const bonusMode = (0, firestore_1.normalizeString)(userData.bonusMode);
    const bonusSource = (0, firestore_1.normalizeString)(userData.bonusSource);
    const bonusActive = bonusExpiresAt != null && bonusExpiresAt.toMillis() > Date.now();
    let kind = null;
    let title = null;
    let message = null;
    let action = null;
    let playerStatus = null;
    if (bonusActive) {
        kind = 'bonusActive';
        title = 'Bonus activ\u00e9';
        message = 'Vous pouvez jouer \u00e0 tous les jeux jusqu\u2019\u00e0 minuit.';
        action = 'bonusActive';
        playerStatus = 'bonus_active';
    }
    else if (shareState.rewardAvailable) {
        kind = 'rewardAvailable';
        title = 'R\u00e9compense disponible';
        message = 'Votre bonus de parrainage est disponible.';
        action = 'rewardAvailable';
        playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    }
    else if (shareState.pendingCount > 0) {
        kind = 'friendPending';
        title = 'Invitation en attente';
        message = 'Un ami n\u2019a pas encore finalis\u00e9 son inscription.';
        action = 'friendPending';
        playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    }
    else if (campaignActive && campaign.kind !== 'defaultInvite') {
        kind = 'specialCampaign';
        title = campaign.title;
        message = campaign.message;
        action = 'specialCampaign';
        playerStatus = remainingPart <= 0 ? 'no_parts' : remainingPart <= 1 ? 'low_parts' : 'normal';
    }
    else if (campaignActive && remainingPart <= 1) {
        kind = 'lowRemainingPlaysInvite';
        title = remainingPart <= 0
            ? 'Plus de chances disponibles'
            : 'Plus qu\u2019une chance disponible';
        message = 'Invitez un proche pour continuer \u00e0 jouer.';
        action = 'lowRemainingPlaysInvite';
        playerStatus = remainingPart <= 0 ? 'no_parts' : 'low_parts';
    }
    else if (campaignActive) {
        kind = 'defaultInvite';
        title = campaign.title;
        message = campaign.message;
        action = 'defaultInvite';
        playerStatus = 'normal';
    }
    else {
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
        campaign: kind == null
            ? null
            : {
                id: firestore_1.campaignId,
                rewardType: campaign.rewardType,
                rewardValue: campaign.rewardValue,
            },
    };
});
exports.createReferral = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const campaign = await loadCampaign();
    if (!(0, firestore_1.isCampaignActive)(campaign)) {
        throw new functions.https.HttpsError('failed-precondition', 'No active share campaign is available.');
    }
    const stateSnap = await firestore_1.refs.shareState(auth.uid).get();
    const state = stateSnap.exists
        ? { ...firestore_1.defaultShareState, ...stateSnap.data() }
        : firestore_1.defaultShareState;
    if (state.grantedCount >= campaign.maxRewardsPerUser) {
        throw new functions.https.HttpsError('resource-exhausted', 'Your reward quota has been reached.');
    }
    const userSnap = await firestore_1.refs.user(auth.uid).get();
    const userData = userSnap.data() ?? {};
    const inviterPseudo = (0, firestore_1.normalizeNullableString)(userData.pseudo) ??
        (0, firestore_1.normalizeNullableString)(userData.display_name) ??
        (0, firestore_1.normalizeNullableString)(userData.first_name);
    const inviteCode = await (0, firestore_1.generateUniqueInviteCode)();
    const referralRef = firestore_1.refs.referrals().doc();
    const referral = {
        campaignId: firestore_1.campaignId,
        inviterUid: auth.uid,
        inviterPseudo,
        inviteeUid: null,
        inviteeContact: (0, firestore_1.normalizeNullableString)(data?.inviteeContact),
        inviteCode,
        shareChannel: (0, firestore_1.normalizeString)(data?.shareChannel) || 'generic',
        status: 'pending',
        rewardStatus: 'not_earned',
        rewardType: campaign.rewardType,
        rewardValue: campaign.rewardValue,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedAt: null,
        rewardGrantedAt: null,
        expiredAt: null,
        createdFromDeviceId: (0, firestore_1.normalizeNullableString)(data?.createdFromDeviceId),
        acceptedFromDeviceId: null,
        metadata: data?.metadata ?? {},
    };
    await referralRef.set(referral);
    await Promise.all([
        firestore_1.refs.shareState(auth.uid).set({
            pendingCount: admin.firestore.FieldValue.increment(1),
            lastReferralAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }),
        (0, firestore_1.recomputeAdminStats)(),
    ]);
    return {
        referralId: referralRef.id,
        inviteCode,
        shareMessage: (0, firestore_1.buildShareMessage)(campaign, inviteCode),
        shareLink: (0, firestore_1.buildShareLink)(inviteCode),
    };
});
exports.validateReferralCode = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, _context) => {
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode).toUpperCase();
    if (!inviteCode) {
        return {
            valid: false,
            inviteCode: '',
            reason: 'empty',
        };
    }
    const referralQuery = await firestore_1.refs
        .referrals()
        .where('inviteCode', '==', inviteCode)
        .limit(1)
        .get();
    if (referralQuery.empty) {
        const legacyUserQuery = await firestore_1.db
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
    const referral = referralQuery.docs[0].data();
    const isPending = referral.status === 'pending' && !referral.inviteeUid;
    return {
        valid: isPending,
        inviteCode,
        reason: isPending ? null : 'already_used',
    };
});
exports.registerReferralAcceptance = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode).toUpperCase();
    if (!inviteCode) {
        throw new functions.https.HttpsError('invalid-argument', 'inviteCode is required.');
    }
    const referralQuery = await firestore_1.refs
        .referrals()
        .where('inviteCode', '==', inviteCode)
        .limit(1)
        .get();
    const referralRef = referralQuery.empty
        ? firestore_1.refs.referrals().doc()
        : referralQuery.docs[0].ref;
    const legacyInviterRef = referralQuery.empty
        ? (await firestore_1.db
            .collection('users')
            .where('referralCode', '==', inviteCode)
            .limit(1)
            .get()).docs[0]?.ref ?? null
        : null;
    if (referralQuery.empty && !legacyInviterRef) {
        throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }
    const campaign = await loadCampaign();
    const acceptanceResult = await firestore_1.db.runTransaction(async (transaction) => {
        const asyncReads = [
            transaction.get(firestore_1.refs.user(auth.uid)),
            transaction.get(firestore_1.refs.referrals().where('inviteeUid', '==', auth.uid).limit(1)),
        ];
        if (referralQuery.empty) {
            asyncReads.unshift(transaction.get(legacyInviterRef));
        }
        else {
            asyncReads.unshift(transaction.get(referralRef));
        }
        const [primarySnap, inviteeUserSnap, existingInviteeReferralSnap] = await Promise.all(asyncReads);
        let inviterUid;
        if (referralQuery.empty) {
            if (!primarySnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Referral not found.');
            }
            inviterUid = primarySnap.id;
        }
        else {
            const referral = primarySnap.data();
            inviterUid = referral.inviterUid;
            if (referral.status !== 'pending' || referral.inviteeUid) {
                throw new functions.https.HttpsError('already-exists', 'This referral has already been accepted.');
            }
        }
        if (inviterUid === auth.uid) {
            throw new functions.https.HttpsError('failed-precondition', 'Self-referrals are not allowed.');
        }
        if (!existingInviteeReferralSnap.empty) {
            throw new functions.https.HttpsError('already-exists', 'A referral has already been used for this account.');
        }
        const rewardStatus = campaign.requireInviteeSignup && !inviteeUserSnap.exists
            ? 'blocked'
            : 'available';
        if (referralQuery.empty) {
            const inviterData = primarySnap.data() ?? {};
            const inviterPseudo = (0, firestore_1.normalizeNullableString)(inviterData.pseudo) ??
                (0, firestore_1.normalizeNullableString)(inviterData.display_name) ??
                (0, firestore_1.normalizeNullableString)(inviterData.first_name);
            const referral = {
                campaignId: firestore_1.campaignId,
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
                acceptedFromDeviceId: (0, firestore_1.normalizeNullableString)(data?.acceptedFromDeviceId),
                metadata: {
                    legacyReferralCode: true,
                },
            };
            transaction.set(referralRef, referral);
        }
        else {
            transaction.update(referralRef, {
                inviteeUid: auth.uid,
                status: 'accepted',
                acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
                acceptedFromDeviceId: (0, firestore_1.normalizeNullableString)(data?.acceptedFromDeviceId),
                rewardStatus,
            });
        }
        return { inviterUid, rewardStatus };
    });
    await Promise.all([
        (0, firestore_1.recomputeShareState)(acceptanceResult.inviterUid),
        (0, firestore_1.recomputeAdminStats)(),
    ]);
    if (acceptanceResult.rewardStatus === 'available') {
        await grantReferralRewardInternal(referralRef.id, 'system/registerReferralAcceptance');
    }
    return {
        success: true,
        referralId: referralRef.id,
    };
});
exports.adminGetNotificationsConfig = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (_data, context) => {
    await requireAdmin(context);
    return loadNotificationsConfig();
});
exports.adminSetNotificationsConfig = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const adminUid = await requireAdmin(context);
    const dailyRemainingChancesReminderEnabled = data?.dailyRemainingChancesReminderEnabled !== false;
    await firestore_1.db.collection('app_config').doc('notifications').set({
        dailyRemainingChancesReminderEnabled,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: firestore_1.refs.user(adminUid),
    }, { merge: true });
    return {
        ok: true,
        dailyRemainingChancesReminderEnabled,
    };
});
exports.grantReferralReward = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const adminUid = await requireAdmin(context);
    const referralId = (0, firestore_1.normalizeString)(data?.referralId);
    if (!referralId) {
        throw new functions.https.HttpsError('invalid-argument', 'referralId is required.');
    }
    return grantReferralRewardInternal(referralId, `admin/${adminUid}`);
});
exports.remindUsersWithRemainingDailyPlays = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule('0 18 * * *')
    .timeZone('Europe/Paris')
    .onRun(async () => {
    const { dailyRemainingChancesReminderEnabled } = await loadNotificationsConfig();
    if (!dailyRemainingChancesReminderEnabled) {
        console.log('[remindUsersWithRemainingDailyPlays] skipped dailyRemainingChancesReminderEnabled=false');
        return null;
    }
    const dateKey = getParisDateKey();
    const usersSnap = await firestore_1.db
        .collection('users')
        .where('remaining_part', '>', 0)
        .get();
    let queued = 0;
    let skippedAlreadyQueued = 0;
    let skippedWithoutParts = 0;
    let failed = 0;
    for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data() ?? {};
        const remainingPart = (0, firestore_1.normalizeNumber)(userData.remaining_part, 0);
        if (remainingPart <= 0) {
            skippedWithoutParts += 1;
            continue;
        }
        const notificationDocId = `daily_remaining_plays_${dateKey}_${userDoc.id}`;
        const notificationRef = firestore_1.db
            .collection(firestore_1.pushNotificationsCollection)
            .doc(notificationDocId);
        const notificationSnap = await notificationRef.get();
        if (notificationSnap.exists) {
            skippedAlreadyQueued += 1;
            continue;
        }
        try {
            const shareStateSnap = await firestore_1.refs.shareState(userDoc.id).get();
            const shareState = shareStateSnap.exists ? shareStateSnap.data() ?? {} : {};
            const lastIndex = parseDailyReminderIndex(shareState.lastDailyPlayReminderIndex);
            const variant = pickDailyPlaysReminderVariant(lastIndex);
            await (0, firestore_1.queueUserPushNotification)({
                docId: notificationDocId,
                title: variant.title,
                body: variant.body,
                userUid: userDoc.id,
                createdBy: 'system/remindUsersWithRemainingDailyPlays',
            });
            await firestore_1.refs.shareState(userDoc.id).set({
                lastDailyPlayReminderDateKey: dateKey,
                lastDailyPlayReminderIndex: variant.index,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            queued += 1;
        }
        catch (error) {
            failed += 1;
            console.log(`[remindUsersWithRemainingDailyPlays] user=${userDoc.id} error=${error}`);
        }
    }
    console.log('[remindUsersWithRemainingDailyPlays] done', JSON.stringify({
        dateKey,
        matchedUsers: usersSnap.size,
        queued,
        skippedAlreadyQueued,
        skippedWithoutParts,
        failed,
    }));
    return null;
});
exports.expireOldReferrals = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule('every 24 hours')
    .timeZone('Europe/Paris')
    .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - firestore_1.defaultReferralExpirationDays * 24 * 60 * 60 * 1000);
    const pendingSnap = await firestore_1.refs
        .referrals()
        .where('status', '==', 'pending')
        .where('createdAt', '<=', cutoff)
        .limit(300)
        .get();
    if (pendingSnap.empty) {
        return null;
    }
    const batch = firestore_1.db.batch();
    const inviterUids = new Set();
    pendingSnap.docs.forEach((doc) => {
        const referral = doc.data();
        inviterUids.add(referral.inviterUid);
        batch.update(doc.ref, {
            status: 'expired',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
    await batch.commit();
    await Promise.all([
        ...Array.from(inviterUids).map((uid) => (0, firestore_1.recomputeShareState)(uid)),
        (0, firestore_1.recomputeAdminStats)(),
    ]);
    return null;
});
exports.adminUpsertSharePromo = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const adminUid = await requireAdmin(context);
    const startAt = (0, firestore_1.toTimestamp)(data?.startAt);
    const endAt = (0, firestore_1.toTimestamp)(data?.endAt);
    if (startAt && endAt && startAt.toMillis() >= endAt.toMillis()) {
        throw new functions.https.HttpsError('invalid-argument', 'startAt must be before endAt.');
    }
    const payload = (0, firestore_1.buildActiveCampaign)({
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
    await firestore_1.refs.sharePromoConfig().set({
        ...payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, firestore_1.recomputeAdminStats)();
    return {
        success: true,
        path: firestore_1.paths.sharePromoConfig,
        campaignId: firestore_1.campaignId,
    };
});
exports.adminGetSharePromoConfig = functions
    .region(firestore_1.region)
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
exports.adminGetSharePromoStats = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (_data, context) => {
    await requireAdmin(context);
    const [stats, recentReferrals, recentRewards, acceptedReferrals] = await Promise.all([
        (0, firestore_1.recomputeAdminStats)(),
        firestore_1.refs.referrals().orderBy('createdAt', 'desc').limit(20).get(),
        firestore_1.refs.rewardEvents().orderBy('createdAt', 'desc').limit(20).get(),
        firestore_1.refs
            .referrals()
            .where('status', '==', 'accepted')
            .orderBy('createdAt', 'desc')
            .limit(100)
            .get(),
    ]);
    const topInvitersMap = new Map();
    acceptedReferrals.docs.forEach((doc) => {
        const inviterUid = (0, firestore_1.normalizeString)(doc.get('inviterUid'));
        topInvitersMap.set(inviterUid, (topInvitersMap.get(inviterUid) ?? 0) + 1);
    });
    return {
        stats: stats ?? firestore_1.defaultAdminStats,
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
