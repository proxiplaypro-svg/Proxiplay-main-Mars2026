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
exports.retryReferralRewards = exports.adminGetSharePromoStats = exports.adminGetSharePromoConfig = exports.adminUpsertSharePromo = exports.grantReferralReward = exports.adminReconcileReferralGameTickets = exports.createReferralGoogleAccount = exports.registerReferralAcceptance = exports.createReferralEmailAccount = exports.createReferral = exports.getSharePromoState = exports.kReferralGameInviteMessage = exports.remindUsersWithRemainingDailyPlays = void 0;
exports.buildReferralGameShareMessage = buildReferralGameShareMessage;
exports.resumeEmailReferralSignups = resumeEmailReferralSignups;
exports.resumeGoogleReferralSignups = resumeGoogleReferralSignups;
const { prepareReferralReward, processReferralReward, retryPendingReferralRewards, pendingRef } = require('../../referral_reward_queue');
const { ensureServerCreatedProfile } = require('../../new_account_profile');
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("./firestore");
const referral_games_1 = require("./referral_games");
const new_account_referral_1 = require("./new_account_referral");
var daily_plays_reminder_1 = require("./daily_plays_reminder");
Object.defineProperty(exports, "remindUsersWithRemainingDailyPlays", { enumerable: true, get: function () { return daily_plays_reminder_1.remindUsersWithRemainingDailyPlays; } });
// Wording while a referral game runs: a referral then gives the inviter a draw
// ticket (no "all games until midnight" access).
exports.kReferralGameInviteMessage = 'Invitez un ami et gagnez un ticket pour le tirage au sort !';
function buildReferralGameShareMessage(inviteCode) {
    return 'Rejoins-moi sur ProxiPlay avec mon code de parrainage ' + inviteCode + ' ! ' +
        'Quand ton inscription est validée, c’est moi qui gagne un ticket pour le tirage au sort.';
}
// An unreadable state (e.g. two games active at once) counts as running, so
// the "until midnight" promise is never shown when it may not apply.
async function isReferralGameRunning() {
    try {
        return (await (0, referral_games_1.findActiveReferralGame)()) != null;
    }
    catch (_) {
        return true;
    }
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
        if (referral.rewardStatus === 'blocked' &&
            referral.metadata?.blockReason !== 'max_rewards_per_user_reached' &&
            referral.metadata?.blockReason !== 'max_rewards_per_invitee_reached') {
            return { granted: false, reason: 'reward_blocked' };
        }
        if (!(0, firestore_1.isAllGamesUntilMidnightReward)(referral.rewardType) &&
            (!(0, firestore_1.isRewardPlayable)(referral.rewardType) || referral.rewardValue <= 0)) {
            return { granted: false, reason: 'unsupported_reward' };
        }
        const inviter = await transaction.get(firestore_1.refs.user(referral.inviterUid));
        const account = inviter.data();
        if (!inviter.exists || require('../../prize_integrity').excluded(account)) {
            return { granted: false, reason: 'inviter_ineligible' };
        }
        const durableReward = await transaction.get(pendingRef(referralId));
        if (durableReward.exists && durableReward.data()?.mode === 'game' &&
            durableReward.data()?.classic_and_game !== true) {
            return { granted: false, reason: 'game_reward_managed' };
        }
        const [inviteeGrantedSnap, eventSnap] = await Promise.all([
            transaction.get(firestore_1.refs
                .referrals()
                .where('inviteeUid', '==', referral.inviteeUid)
                .where('rewardStatus', '==', 'granted').limit(1)),
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
            return { granted: false, reason: 'missing_acceptance_date' };
        }
        const deadline = newRule && referral.acceptedAt
            ? (0, firestore_1.getNextMidnightTimestamp)(referral.acceptedAt)
            : undefined;
        const existingAccess = account?.allGamesAccessUntil;
        const accessUntil = deadline && existingAccess?.toMillis &&
            existingAccess.toMillis() > deadline.toMillis() ? existingAccess : deadline;
        const previousReferralAccess = account?.referralBonusExpiresAt;
        const referralAccessUntil = deadline && previousReferralAccess?.toMillis &&
            previousReferralAccess.toMillis() > deadline.toMillis() ? previousReferralAccess : deadline;
        transaction.set(eventRef, (0, firestore_1.buildRewardEvent)(referral.inviterUid, referralId, { ...campaign, rewardType: referral.rewardType, rewardValue: referral.rewardValue }, grantedBy));
        await (0, firestore_1.applyRewardToUser)(transaction, referral.inviterUid, referral.rewardType, referral.rewardValue, accessUntil, referralAccessUntil);
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
        const validAccess = referral.metadata?.playerRewardRuleVersion !== 2 ||
            (referral.acceptedAt != null &&
                (0, firestore_1.getNextMidnightTimestamp)(referral.acceptedAt).toMillis() > Date.now());
        if ((0, firestore_1.isAllGamesUntilMidnightReward)(referral.rewardType) && validAccess) {
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
    // During a referral game a new referral gives a draw ticket instead of
    // the "all games until midnight" access this banner promises, so it is
    // hidden (the referral game card invites instead). Unknown state hides it.
    const referralGameActive = await isReferralGameRunning();
    if (referralGameActive && kind != null)
        message = exports.kReferralGameInviteMessage;
    return {
        showBanner: kind != null && !referralGameActive,
        referralGameActive,
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
    const userSnap = await firestore_1.refs.user(auth.uid).get();
    const userData = userSnap.data() ?? {};
    const inviterRole = (0, firestore_1.normalizeString)(userData.user_role) || (0, firestore_1.normalizeString)(userData.userRole);
    if (!userSnap.exists || inviterRole !== 'joueur' ||
        require('../../prize_integrity').excluded(userData)) {
        throw new functions.https.HttpsError('permission-denied', 'A player account is required.');
    }
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
    const referralGameActive = await isReferralGameRunning();
    return {
        referralId: referralRef.id,
        inviteCode,
        shareMessage: referralGameActive ?
            buildReferralGameShareMessage(inviteCode) : (0, firestore_1.buildShareMessage)(campaign, inviteCode),
        shareLink: (0, firestore_1.buildShareLink)(inviteCode),
        referralGameActive,
    };
});
// Referral signup operations are server-owned and contain no password.
exports.createReferralEmailAccount = functions.region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const crypto = require('crypto');
    const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
    const requestId = typeof data?.requestId === 'string' ? data.requestId : '';
    const email = typeof data?.email === 'string' ? data.email.trim().toLowerCase() : '';
    const password = typeof data?.password === 'string' ? data.password : '';
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode);
    if (!/^[0-9a-f-]{36}$/i.test(requestId) || !email.includes('@') || email.length > 254 ||
        password.length < 6 || password.length > 128 || !inviteCode || inviteCode.length > 128) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid signup details.');
    }
    // The framework-resolved address depends on the deployment proxy configuration.
    // Verify it before rollout; never log credentials or the raw address.
    const ip = context.rawRequest?.ip || context.rawRequest?.socket?.remoteAddress;
    if (!ip)
        throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    const now = Date.now();
    const rate = firestore_1.db.collection('_referral_signup_rate').doc(hash(ip));
    await firestore_1.db.runTransaction(async (tx) => {
        const previous = (await tx.get(rate)).data() ?? {};
        const start = Number(previous.start) || 0;
        const count = now >= start && now - start < 60000 ? Number(previous.count) || 0 : 0;
        if (count >= 5)
            throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
        tx.set(rate, { start: count ? start : now, count: count + 1 });
    });
    const found = await firestore_1.refs.referrals().where('inviteCode', '==', inviteCode).limit(1).get();
    if (found.empty)
        throw new functions.https.HttpsError('not-found', 'Referral not found.');
    const referralRef = found.docs[0].ref;
    // A shared per-invitation quota also limits distributed attempts against a
    // valid code. This supplements the network quota; it is not attestation.
    const codeRate = firestore_1.db.collection('_referral_signup_code_rate').doc(hash(referralRef.id));
    await firestore_1.db.runTransaction(async (tx) => {
        const previous = (await tx.get(codeRate)).data() ?? {};
        const start = Number(previous.start) || 0;
        const count = now >= start && now - start < 60000 ? Number(previous.count) || 0 : 0;
        if (count >= 10)
            throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
        tx.set(codeRate, { start: count ? start : now, count: count + 1 });
    });
    const operationRef = firestore_1.db.collection('_referral_signup_operations').doc(hash(requestId));
    const uid = 'ref_' + hash(requestId).slice(0, 48);
    await firestore_1.db.runTransaction(async (tx) => {
        const [opSnap, referralSnap] = await Promise.all([tx.get(operationRef), tx.get(referralRef)]);
        const op = opSnap.data();
        const referral = referralSnap.data();
        if (op) {
            if (op.uid !== uid || op.emailHash !== hash(email) || op.referralId !== referralRef.id)
                throw new functions.https.HttpsError('failed-precondition', 'Signup details changed.');
            return;
        }
        if (!referral || referral.status !== 'pending' || referral.inviteeUid)
            throw new functions.https.HttpsError('failed-precondition', 'Referral unavailable.', { reason: 'referral_unavailable', accountCreated: false });
        tx.create(operationRef, { uid, emailHash: hash(email), referralId: referralRef.id, status: 'pending', createdAt: admin.firestore.FieldValue.serverTimestamp() });
    });
    try {
        await admin.auth().createUser({ uid, email, password });
    }
    catch (error) {
        // Only recover our server-assigned UID, never a pre-existing account found
        // by email. Other Auth errors leave the operation retryable.
        let user;
        try {
            user = await admin.auth().getUser(uid);
        }
        catch (_) { /* no matching UID */ }
        if (!user || user.email?.trim().toLowerCase() !== email) {
            if (error?.code === 'auth/email-already-exists')
                throw new functions.https.HttpsError('already-exists', 'Account already exists.', { reason: 'email_exists', accountCreated: false });
            throw new functions.https.HttpsError('unavailable', 'Could not create account.');
        }
    }
    // The account of this operation exists (created or matched by UID and
    // address above): its player profile is created by the server, before
    // the referral is accepted.
    await ensureServerCreatedProfile(firestore_1.db, { uid, email, role: 'joueur' });
    const result = await completeEmailReferralSignup(operationRef, uid, hash(email), referralRef.id);
    try {
        await processReferralReward(referralRef.id, grantReferralRewardInternal);
    }
    catch (_) {
        functions.logger.error('REFERRAL_REWARD_DEFERRED', { referralId: referralRef.id });
    }
    try {
        await Promise.all([(0, firestore_1.recomputeShareState)(result.inviterUid), (0, firestore_1.recomputeAdminStats)()]);
    }
    catch (_) {
        functions.logger.warn('REFERRAL_STATS_DEFERRED');
    }
    return { success: true };
});
// Acceptance of the referral of an e-mail signup operation whose account and
// player profile exist. Shared by the callable and the scheduled resume; one
// transaction, so a referral is accepted (and its reward queued) only once.
async function completeEmailReferralSignup(operationRef, uid, emailHash, expectedReferralId) {
    return firestore_1.db.runTransaction(async (tx) => {
        const op = (await tx.get(operationRef)).data();
        if (!op || op.uid !== uid || op.emailHash !== emailHash || typeof op.referralId !== 'string' ||
            (expectedReferralId && op.referralId !== expectedReferralId))
            throw new functions.https.HttpsError('failed-precondition', 'Invalid signup operation.');
        const referralRef = firestore_1.refs.referrals().doc(op.referralId);
        const [referralSnap, existing] = await Promise.all([
            tx.get(referralRef), tx.get(firestore_1.refs.referrals().where('inviteeUid', '==', uid).limit(1)),
        ]);
        const referral = referralSnap.data();
        if (!referral)
            throw new functions.https.HttpsError('failed-precondition', 'Invalid signup operation.');
        if (referral.status === 'accepted' && referral.inviteeUid === uid)
            return { inviterUid: referral.inviterUid };
        if (referral.inviterUid === uid || !existing.empty || referral.status !== 'pending' || referral.inviteeUid)
            throw new functions.https.HttpsError('already-exists', 'Referral unavailable.', { reason: 'referral_unavailable', accountCreated: true });
        const acceptedAt = admin.firestore.Timestamp.now();
        // During an active referral game the ticket replaces the classic reward.
        const event = await prepareReferralReward(tx, referralRef.id, referral.inviterUid, acceptedAt);
        tx.create(pendingRef(referralRef.id), event);
        tx.update(referralRef, { inviteeUid: uid, status: 'accepted', acceptedAt, rewardStatus: 'available',
            rewardType: 'all_games_until_midnight', rewardValue: 1,
            metadata: { ...(referral.metadata ?? {}), playerRewardRuleVersion: 2 } });
        tx.update(operationRef, { status: 'completed', completedAt: admin.firestore.FieldValue.serverTimestamp() });
        return { inviterUid: referral.inviterUid };
    });
}
// Scheduled resume of e-mail signups interrupted after the account was
// created (the player may then have signed in from the login page, whose
// profile has no role): the player profile is completed and the referral
// accepted. Only the account of the operation (its UID, with the address the
// operation recorded) is ever touched.
async function resumeEmailReferralSignups(nowMs = Date.now()) {
    const crypto = require('crypto');
    const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
    const pending = await firestore_1.db.collection('_referral_signup_operations').where('status', '==', 'pending').limit(50).get();
    let resumed = 0, abandoned = 0, refused = 0;
    for (const doc of pending.docs) {
        const op = doc.data();
        const createdMs = typeof op.createdAt?.toMillis === 'function' ? op.createdAt.toMillis() : NaN;
        if (!Number.isFinite(createdMs) || nowMs - createdMs < 2 * 60 * 1000)
            continue; // Leave the live call finish.
        try {
            let user;
            try {
                user = await admin.auth().getUser(op.uid);
            }
            catch (error) {
                if (error?.code !== 'auth/user-not-found')
                    throw error;
            }
            if (!user) {
                // No account was ever created for this operation.
                if (nowMs - createdMs >= kGoogleSignupAbandonMs) {
                    await doc.ref.update({ status: 'completed', outcome: 'abandoned' });
                    abandoned++;
                }
                continue;
            }
            const email = (0, new_account_referral_1.normalizeEmail)(user.email);
            if (!email || hash(email) !== op.emailHash) {
                functions.logger.error('REFERRAL_EMAIL_SIGNUP_RESUME_MISMATCH', { operation: doc.id });
                continue;
            }
            try {
                await ensureServerCreatedProfile(firestore_1.db, { uid: user.uid, email, role: 'joueur' });
                const result = await completeEmailReferralSignup(doc.ref, user.uid, op.emailHash);
                resumed++;
                try {
                    await Promise.all([(0, firestore_1.recomputeShareState)(result.inviterUid), (0, firestore_1.recomputeAdminStats)()]);
                }
                catch (_) {
                    functions.logger.warn('REFERRAL_STATS_DEFERRED');
                }
            }
            catch (error) {
                // Referral already used or profile of another role: closed, never retried.
                if (error?.code !== 'already-exists' && error?.details?.reason !== 'profile_conflict')
                    throw error;
                await doc.ref.update({ status: 'completed', outcome: 'refused',
                    reason: error?.details?.reason || 'referral_unavailable' });
                refused++;
            }
        }
        catch (_) {
            functions.logger.error('REFERRAL_EMAIL_SIGNUP_RESUME_FAILED', { operation: doc.id });
        }
    }
    return { resumed, abandoned, refused };
}
async function findPendingReferralByCode(inviteCode) {
    const referralQuery = await firestore_1.refs.referrals().where('inviteCode', '==', inviteCode).limit(1).get();
    if (referralQuery.empty) {
        throw new functions.https.HttpsError('not-found', 'Referral not found.');
    }
    return referralQuery.docs[0].ref;
}
// Reward processing and stats after a durable acceptance. Both are retried
// by the scheduled worker if they fail here.
async function afterNewAccountReferral(referralId, outcome) {
    if (!outcome.accepted)
        return;
    try {
        await processReferralReward(referralId, grantReferralRewardInternal);
    }
    catch (_) {
        functions.logger.error('REFERRAL_REWARD_DEFERRED', { referralId });
    }
    try {
        await Promise.all([(0, firestore_1.recomputeShareState)(outcome.inviterUid), (0, firestore_1.recomputeAdminStats)()]);
    }
    catch (_) {
        functions.logger.warn('REFERRAL_STATS_DEFERRED');
    }
}
// Transition only, for app 1.1.1 which creates the account itself and sends
// the code afterwards (app 1.1.2 never calls this). Closed 4 weeks after the
// real publication of 1.1.2 (app_config/referral_signup).
exports.registerReferralAcceptance = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const auth = requireAuth(context);
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode);
    if (!inviteCode) {
        throw new functions.https.HttpsError('invalid-argument', 'inviteCode is required.');
    }
    if (!(await (0, new_account_referral_1.isLegacyTransitionOpen)(Date.now()))) {
        throw new functions.https.HttpsError('failed-precondition', 'Referral codes are reserved to newly created accounts.', { reason: 'update_required' });
    }
    const referralRef = await findPendingReferralByCode(inviteCode);
    let user;
    try {
        user = await admin.auth().getUser(auth.uid);
    }
    catch (_) {
        throw new functions.https.HttpsError('failed-precondition', 'Referral codes are reserved to newly created accounts.');
    }
    const creationMs = Date.parse(user.metadata.creationTime);
    const inviteeSnap = await firestore_1.refs.user(auth.uid).get();
    const invitee = inviteeSnap.data() ?? {};
    // The player referral program is for players only. App 1.1.1 also sends
    // the code typed in its merchant signup form here: a merchant account
    // never earns a player reward (the merchant referral program is separate).
    if ((0, firestore_1.normalizeString)(invitee.user_role) === 'commercant') {
        throw new functions.https.HttpsError('failed-precondition', 'Referral codes are reserved to new player accounts.', { reason: 'merchant_account' });
    }
    // Only the session that created the account, before any game: an
    // existing account entering a code never counts, whatever its profile.
    if (!(0, new_account_referral_1.isAccountCreationSession)(auth.token.auth_time, creationMs) ||
        Number(invitee.games_played_count) > 0 || invitee.last_real_activity_at != null) {
        throw new functions.https.HttpsError('failed-precondition', 'Referral codes are reserved to newly created accounts.');
    }
    const outcome = await (0, new_account_referral_1.acceptReferralForNewAccount)({
        referralRef,
        uid: auth.uid,
        referralFields: { acceptedFromDeviceId: (0, firestore_1.normalizeNullableString)(data?.acceptedFromDeviceId) },
    });
    if (!outcome.accepted) {
        const code = outcome.reason === 'self_referral' ?
            'failed-precondition' : 'already-exists';
        throw new functions.https.HttpsError(code, 'Referral unavailable.', { reason: outcome.reason });
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
// Statuses: accepted | existing_account | refused.
// Order: authentic Google token, then existing account (answered whatever the
// code, so its owner signs in normally), then the code, for a new account only.
// Never deletes an account: after a failure the operation is resumed by the
// next call or by the scheduled worker.
exports.createReferralGoogleAccount = functions.region(firestore_1.region)
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
    const crypto = require('crypto');
    const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
    const idToken = typeof data?.idToken === 'string' ? data.idToken : '';
    const inviteCode = (0, firestore_1.normalizeString)(data?.inviteCode);
    const claims = idToken.length <= 8192 ? (0, new_account_referral_1.readUnverifiedGoogleClaims)(idToken) : null;
    if (!claims || !inviteCode || inviteCode.length > 128) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid signup details.');
    }
    const ip = context.rawRequest?.ip || context.rawRequest?.socket?.remoteAddress;
    if (!ip)
        throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    const now = Date.now();
    const rate = firestore_1.db.collection('_referral_signup_rate').doc(hash(ip));
    await firestore_1.db.runTransaction(async (tx) => {
        const previous = (await tx.get(rate)).data() ?? {};
        const start = Number(previous.start) || 0;
        const count = now >= start && now - start < 60000 ? Number(previous.count) || 0 : 0;
        if (count >= 5)
            throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts.');
        tx.set(rate, { start: count ? start : now, count: count + 1 });
    });
    const identity = await (0, new_account_referral_1.verifyGoogleIdToken)(idToken);
    if (!identity || identity.sub !== claims.sub) {
        throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
    }
    const operationRef = (0, new_account_referral_1.googleSignupRef)(identity.sub);
    let op = (await operationRef.get()).data();
    if (op?.status === 'completed') {
        // Same person calling again: only answered after proving the identity.
        const idp = await (0, new_account_referral_1.signInWithGoogleIdToken)(idToken);
        if (idp.sub !== identity.sub || idp.uid !== op.uid) {
            throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
        }
        return { status: op.outcome === 'accepted' ? 'accepted' : 'refused' };
    }
    if (!op) {
        // The operation is opened only once Firebase has no account for this
        // Google identity or address. An existing account never gets one, and
        // its code is not even read.
        const checkedAbsentAt = Date.now();
        if (await (0, new_account_referral_1.findGoogleAccount)(identity)) {
            return { status: 'existing_account' };
        }
        const referralRef = await findPendingReferralByCode(inviteCode);
        const referral = (await referralRef.get()).data();
        if (!referral || referral.status !== 'pending' || referral.inviteeUid) {
            throw new functions.https.HttpsError('failed-precondition', 'Referral unavailable.', { reason: 'referral_unavailable' });
        }
        try {
            await operationRef.create({
                status: 'pending', googleSub: identity.sub, referralId: referralRef.id,
                checkedAbsentAt, created_at: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        catch (error) {
            if (error?.code !== 6)
                throw error; // 6 = ALREADY_EXISTS: concurrent call.
        }
        op = (await operationRef.get()).data();
        if (!op)
            throw new functions.https.HttpsError('unavailable', 'Signup unavailable.');
    }
    // Firebase creates the account (or not) and says which. Identity is
    // established here: the operation must belong to this Google account.
    const idp = await (0, new_account_referral_1.signInWithGoogleIdToken)(idToken);
    if (idp.sub !== op.googleSub) {
        throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
    }
    const outcome = await completeGoogleReferralSignup(operationRef, op, idp.uid, idp.isNewUser);
    return { status: outcome.accepted ? 'accepted' : outcome.reason === 'existing_account' ? 'existing_account' : 'refused' };
});
async function completeGoogleReferralSignup(operationRef, op, uid, reportedNew) {
    if (op.uid && op.uid !== uid) {
        return { accepted: false, reason: 'operation_mismatch' };
    }
    const owned = reportedNew || op.uid === uid ||
        (0, new_account_referral_1.accountBelongsToOperation)(await (0, new_account_referral_1.authCreationMs)(uid), Number(op.checkedAbsentAt));
    if (!owned) {
        await operationRef.update({ status: 'completed', outcome: 'refused', reason: 'existing_account', uid });
        return { accepted: false, reason: 'existing_account' };
    }
    // Recorded first: a crash below leaves a resumable operation with its uid.
    if (!op.uid)
        await operationRef.update({ uid });
    const referralRef = firestore_1.refs.referrals().doc(op.referralId);
    const outcome = await (0, new_account_referral_1.acceptReferralForNewAccount)({ referralRef, uid, operationRef });
    await afterNewAccountReferral(referralRef.id, outcome);
    return outcome;
}
// Scheduled recovery of Google signups interrupted after the operation was
// opened (app closed, network lost, function crash). Never deletes anything.
const kGoogleSignupAbandonMs = 60 * 60 * 1000;
async function resumeGoogleReferralSignups(nowMs = Date.now()) {
    const pending = await firestore_1.db.collection('_referral_google_signups').where('status', '==', 'pending').limit(50).get();
    let resumed = 0, abandoned = 0;
    for (const doc of pending.docs) {
        const op = doc.data();
        if (nowMs - Number(op.checkedAbsentAt) < 2 * 60 * 1000)
            continue; // Leave the live call finish.
        try {
            let uid = typeof op.uid === 'string' ? op.uid : '';
            if (!uid) {
                try {
                    uid = (await admin.auth().getUserByProviderUid('google.com', op.googleSub)).uid;
                }
                catch (error) {
                    if (error?.code !== 'auth/user-not-found')
                        throw error;
                }
            }
            if (!uid) {
                // No account was ever created for this operation.
                if (nowMs - Number(op.checkedAbsentAt) >= kGoogleSignupAbandonMs) {
                    await doc.ref.update({ status: 'completed', outcome: 'abandoned' });
                    abandoned++;
                }
                continue;
            }
            await completeGoogleReferralSignup(doc.ref, op, uid, false);
            resumed++;
        }
        catch (_) {
            functions.logger.error('REFERRAL_GOOGLE_SIGNUP_RESUME_FAILED', { operation: doc.id });
        }
    }
    return { resumed, abandoned };
}
exports.adminReconcileReferralGameTickets = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .https.onCall(async (data, context) => {
    await requireAdmin(context);
    const gameId = (0, firestore_1.normalizeString)(data?.gameId);
    if (!gameId || gameId.includes('/')) {
        throw new functions.https.HttpsError('invalid-argument', 'gameId is required.');
    }
    return (0, referral_games_1.reconcileReferralGameTickets)(gameId);
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
// Invitations never expire: the former daily expireOldReferrals job is
// removed (it is deleted from production with the referral lot).
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
// Recovery only: a referral reward is granted in the signup call itself. This
// worker resumes the rare interrupted cases, so every 10 minutes is enough.
exports.retryReferralRewards = functions.region(firestore_1.region).runWith({ timeoutSeconds: 540, memory: '512MB' }).pubsub.schedule('every 10 minutes').onRun(async () => {
    // Signups first: a resumed acceptance enqueues its reward below.
    await resumeGoogleReferralSignups();
    await resumeEmailReferralSignups();
    return retryPendingReferralRewards(grantReferralRewardInternal);
});
