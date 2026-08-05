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
exports.adminGetSharePromoStats = exports.adminGetSharePromoConfig = exports.adminUpsertSharePromo = exports.expireOldReferrals = exports.grantReferralReward = exports.registerReferralAcceptance = exports.createReferral = exports.getSharePromoState = exports.remindUsersWithRemainingDailyPlays = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("./firestore");
const referral_games_1 = require("./referral_games");
var daily_plays_reminder_1 = require("./daily_plays_reminder");
Object.defineProperty(exports, "remindUsersWithRemainingDailyPlays", { enumerable: true, get: function () { return daily_plays_reminder_1.remindUsersWithRemainingDailyPlays; } });
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
        const [inviterGrantedSnap, inviteeGrantedSnap, eventSnap] = await Promise.all([
            transaction.get(firestore_1.refs
                .referrals()
                .where('inviterUid', '==', referral.inviterUid)
                .where('rewardStatus', '==', 'granted')),
            transaction.get(firestore_1.refs
                .referrals()
                .where('inviteeUid', '==', referral.inviteeUid)
                .where('rewardStatus', '==', 'granted')),
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
        transaction.set(eventRef, (0, firestore_1.buildRewardEvent)(referral.inviterUid, referralId, campaign, grantedBy));
        await (0, firestore_1.applyRewardToUser)(transaction, referral.inviterUid, referral.rewardType, referral.rewardValue);
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
            followUpTasks.push((0, firestore_1.queueUserPushNotification)({
                docId: `share_promo_reward_${referralId}`,
                title: '🎉 Ton parrainage a fonctionné !',
                body: 'Tu peux maintenant jouer à tous les jeux jusqu’à minuit.',
                userUid: referral.inviterUid,
                createdBy: grantedBy,
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
    let kind = null;
    let title = null;
    let message = null;
    let action = null;
    if (shareState.rewardAvailable) {
        kind = 'rewardAvailable';
        title = 'Récompense disponible';
        message = 'Votre bonus de parrainage est disponible.';
        action = 'rewardAvailable';
    }
    else if (shareState.pendingCount > 0) {
        kind = 'friendPending';
        title = 'Invitation en attente';
        message = 'Un ami n’a pas encore finalisé son inscription.';
        action = 'friendPending';
    }
    else if (campaignActive && campaign.kind !== 'defaultInvite') {
        kind = 'specialCampaign';
        title = campaign.title;
        message = campaign.message;
        action = 'specialCampaign';
    }
    else if (campaignActive && remainingPart <= 1) {
        kind = 'lowRemainingPlaysInvite';
        title = remainingPart <= 0
            ? 'Plus de chances disponibles'
            : 'Plus qu’une chance disponible';
        message = 'Invitez un proche pour continuer à jouer.';
        action = 'lowRemainingPlaysInvite';
    }
    else if (campaignActive) {
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
exports.registerReferralAcceptance = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode);
    if (!inviteCode) {
        throw new functions.https.HttpsError('invalid-argument', 'inviteCode is required.');
    }
    const referralQuery = await firestore_1.refs
        .referrals()
        .where('inviteCode', '==', inviteCode)
        .limit(1)
        .get();
    if (referralQuery.empty) {
        throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }
    const campaign = await loadCampaign();
    const referralRef = referralQuery.docs[0].ref;
    const acceptanceResult = await firestore_1.db.runTransaction(async (transaction) => {
        const [referralSnap, inviteeUserSnap, existingInviteeReferralSnap] = await Promise.all([
            transaction.get(referralRef),
            transaction.get(firestore_1.refs.user(auth.uid)),
            transaction.get(firestore_1.refs.referrals().where('inviteeUid', '==', auth.uid).limit(1)),
        ]);
        const referral = referralSnap.data();
        if (referral.inviterUid === auth.uid) {
            throw new functions.https.HttpsError('failed-precondition', 'Self-referrals are not allowed.');
        }
        if (!existingInviteeReferralSnap.empty) {
            throw new functions.https.HttpsError('already-exists', 'A referral has already been used for this account.');
        }
        if (referral.status !== 'pending' || referral.inviteeUid) {
            throw new functions.https.HttpsError('already-exists', 'This referral has already been accepted.');
        }
        const rewardStatus = campaign.requireInviteeSignup && !inviteeUserSnap.exists
            ? 'blocked'
            : 'available';
        transaction.update(referralRef, {
            inviteeUid: auth.uid,
            status: 'accepted',
            acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
            acceptedFromDeviceId: (0, firestore_1.normalizeNullableString)(data?.acceptedFromDeviceId),
            rewardStatus,
        });
        return { inviterUid: referral.inviterUid, rewardStatus };
    });
    await Promise.all([
        (0, firestore_1.recomputeShareState)(acceptanceResult.inviterUid),
        (0, firestore_1.recomputeAdminStats)(),
    ]);
    // Le filleul vient d'utiliser le code pour creer son compte : c'est ce
    // qui compte comme parrainage valide. S'il existe un jeu de parrainage
    // actif, ce parrainage donne un ticket de tirage au sort a la place de
    // la recompense classique (remplacement conditionne a l'existence d'un
    // jeu actif, pas une bascule definitive -- voir referral_games.ts).
    const activeReferralGame = await (0, referral_games_1.findActiveReferralGame)();
    if (activeReferralGame) {
        await (0, referral_games_1.addReferralGameTicket)(activeReferralGame.id, acceptanceResult.inviterUid, referralRef.id);
    }
    else if (acceptanceResult.rewardStatus === 'available') {
        await grantReferralRewardInternal(referralRef.id, 'system/registerReferralAcceptance');
    }
    return {
        success: true,
        referralId: referralRef.id,
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
