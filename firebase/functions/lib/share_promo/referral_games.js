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
    if (active.length > 1) {
        console.warn(`[referral_games] ${active.length} jeux de parrainage actifs simultanement, utilisation du premier (${active[0].id}).`);
    }
    return { id: active[0].id, data: active[0].data() };
}
async function addReferralGameTicket(gameId, inviterUid, referralId) {
    const gameRef = referralGamesCollection().doc(gameId);
    await firestore_1.db.runTransaction(async (transaction) => {
        transaction.set(gameRef.collection('entries').doc(), {
            inviter_uid: inviterUid,
            referral_id: referralId,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        transaction.set(gameRef, { ticket_count: admin.firestore.FieldValue.increment(1) }, { merge: true });
    });
}
