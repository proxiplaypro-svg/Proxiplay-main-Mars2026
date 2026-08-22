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
exports.findActiveReferralGame = findActiveReferralGame;
exports.addReferralGameTicket = addReferralGameTicket;
exports.reconcileReferralGameTickets = reconcileReferralGameTickets;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("./firestore");
const referralGamesCollection = () => firestore_1.db.collection('referral_games');
async function findActiveReferralGame(now = admin.firestore.Timestamp.now()) {
    const snap = await referralGamesCollection()
        .where('status', '==', 'active')
        .get();
    const active = snap.docs.filter((doc) => {
        const data = doc.data();
        const startMs = data.start_date?.toMillis?.() ?? null;
        const endMs = data.end_date?.toMillis?.() ?? null;
        if (startMs == null || endMs == null) {
            return false;
        }
        return startMs <= now.toMillis() && now.toMillis() <= endMs;
    });
    if (active.length === 0) {
        return null;
    }
    if (active.length > 1)
        throw new Error('Multiple referral games are active simultaneously.');
    return { id: active[0].id, data: active[0].data() };
}
async function addReferralGameTicket(gameId, referralId, now = admin.firestore.Timestamp.now()) {
    const gameRef = referralGamesCollection().doc(gameId);
    const referralRef = firestore_1.refs.referral(referralId);
    const entryRef = gameRef.collection('entries').doc(referralId);
    return firestore_1.db.runTransaction(async (transaction) => {
        const [gameSnap, referralSnap, entrySnap] = await Promise.all([
            transaction.get(gameRef),
            transaction.get(referralRef),
            transaction.get(entryRef),
        ]);
        if (entrySnap.exists)
            return 'already_exists';
        if (!gameSnap.exists || !referralSnap.exists)
            return 'ineligible';
        const game = gameSnap.data();
        const referral = referralSnap.data();
        const startMs = game.start_date?.toMillis?.();
        const endMs = game.end_date?.toMillis?.();
        if (game.status !== 'active' || startMs == null || endMs == null || startMs > now.toMillis() || endMs < now.toMillis())
            return 'ineligible';
        if (referral.status !== 'accepted' || !referral.inviterUid?.trim())
            return 'ineligible';
        const inviterRef = firestore_1.refs.user(referral.inviterUid);
        const inviterSnap = await transaction.get(inviterRef);
        const inviter = inviterSnap.data();
        const accountStatus = String(inviter?.account_status ?? '').trim().toLowerCase();
        const playerStatus = String(inviter?.player_status_cached ?? '').trim().toLowerCase();
        if (!inviterSnap.exists || inviter?.auto_deleted === true || inviter?.deleted === true || accountStatus === 'rejected' || accountStatus === 'suspended' || playerStatus === 'suspended' || playerStatus === 'suspendu')
            return 'ineligible';
        transaction.set(entryRef, {
            inviter_uid: referral.inviterUid,
            referral_id: referralId,
            inviter_ref: inviterRef,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        transaction.set(gameRef, { ticket_count: admin.firestore.FieldValue.increment(1) }, { merge: true });
        return 'created';
    });
}
async function reconcileReferralGameTickets(gameId) {
    const gameSnap = await referralGamesCollection().doc(gameId).get();
    if (!gameSnap.exists)
        throw new Error('Referral game not found.');
    const game = gameSnap.data();
    const startMs = game.start_date?.toMillis?.();
    const endMs = game.end_date?.toMillis?.();
    if (startMs == null || endMs == null)
        throw new Error('Referral game has invalid dates.');
    const acceptedSnap = await firestore_1.refs.referrals().where('status', '==', 'accepted').get();
    const results = { created: 0, already_exists: 0, ineligible: 0 };
    for (const referralDoc of acceptedSnap.docs) {
        const referral = referralDoc.data();
        if (!referral.acceptedAt || referral.acceptedAt.toMillis() < startMs || referral.acceptedAt.toMillis() > endMs)
            continue;
        results[await addReferralGameTicket(gameId, referralDoc.id, referral.acceptedAt)] += 1;
    }
    return results;
}
