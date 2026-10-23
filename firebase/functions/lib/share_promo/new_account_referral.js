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
exports.referralSignupConfigRef = exports.kLegacyTransitionMs = exports.googleSignupRef = exports.emailRegistryRef = exports.kEmailRegistryRetentionMs = void 0;
exports.normalizeEmail = normalizeEmail;
exports.emailRegistryKey = emailRegistryKey;
exports.isRegistryEntryActive = isRegistryEntryActive;
exports.recordDeletedAccountEmail = recordDeletedAccountEmail;
exports.acceptReferralForNewAccount = acceptReferralForNewAccount;
exports.readUnverifiedGoogleClaims = readUnverifiedGoogleClaims;
exports.signInWithGoogleIdToken = signInWithGoogleIdToken;
exports.authCreationMs = authCreationMs;
exports.accountBelongsToOperation = accountBelongsToOperation;
exports.findGoogleAccount = findGoogleAccount;
exports.isLegacyTransitionOpen = isLegacyTransitionOpen;
exports.isAccountCreationSession = isAccountCreationSession;
// A referral is only valid when it is attached to the creation of a new
// ProxiPlay account, by e-mail or by Google. Firebase Authentication itself is
// the judge of "new": the e-mail path creates the account server-side
// (createUser fails for a known address), the Google path asks the Auth REST
// endpoint accounts:signInWithIdp, whose isNewUser flag is set by Firebase.
// Nothing here relies on a time window.
const { prepareReferralReward, pendingRef } = require('../../referral_reward_queue');
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("./firestore");
// --- Anti-abuse registry ----------------------------------------------------
// HMAC of the normalized address, never the address itself. Written when a
// referral is accepted and when an account is deleted, so a deleted then
// recreated account (new for Firebase) is not referred again. Entries expire
// after 2 years: checked on read, removed by a Firestore TTL policy on
// expires_at once activated.
exports.kEmailRegistryRetentionMs = 730 * 24 * 60 * 60 * 1000;
const kEmailRegistryCollection = '_referral_email_registry';
function normalizeEmail(email) {
    return typeof email === 'string' ? email.trim().toLowerCase() : '';
}
// Throws (fail closed) when the server key is missing: no referral is then
// accepted rather than one recorded without protection.
function emailRegistryKey(email) {
    const secret = process.env.REFERRAL_EMAIL_HMAC_KEY || '';
    if (secret.length < 32) {
        functions.logger.error('REFERRAL_EMAIL_HMAC_KEY_MISSING');
        throw new functions.https.HttpsError('unavailable', 'Referral unavailable.');
    }
    return crypto.createHmac('sha256', secret).update(normalizeEmail(email)).digest('hex');
}
const emailRegistryRef = (key) => firestore_1.db.collection(kEmailRegistryCollection).doc(key);
exports.emailRegistryRef = emailRegistryRef;
function isRegistryEntryActive(snap, nowMs) {
    const expiresAt = snap.get('expires_at');
    return snap.exists && typeof expiresAt?.toMillis === 'function' && expiresAt.toMillis() > nowMs;
}
function registryEntry(kind, nowMs) {
    return {
        kind,
        created_at: admin.firestore.Timestamp.fromMillis(nowMs),
        expires_at: admin.firestore.Timestamp.fromMillis(nowMs + exports.kEmailRegistryRetentionMs),
    };
}
// Best effort, called on account deletion: never blocks the deletion itself.
async function recordDeletedAccountEmail(email) {
    const address = normalizeEmail(email);
    if (!address)
        return;
    try {
        await (0, exports.emailRegistryRef)(emailRegistryKey(address)).set(registryEntry('deleted_account', Date.now()));
    }
    catch (_) {
        functions.logger.error('REFERRAL_EMAIL_REGISTRY_DELETE_NOT_RECORDED');
    }
}
// One transaction for every path: the same referral, invitee or address can
// never be rewarded twice, even under concurrent calls. A business refusal is
// returned (not thrown) so the operation record is updated atomically.
async function acceptReferralForNewAccount(params) {
    const { referralRef, uid, emailKey, operationRef } = params;
    return firestore_1.db.runTransaction(async (tx) => {
        const [referralSnap, inviteeReferrals, registrySnap] = await Promise.all([
            tx.get(referralRef),
            tx.get(firestore_1.db.collection('referrals').where('inviteeUid', '==', uid).limit(1)),
            tx.get((0, exports.emailRegistryRef)(emailKey)),
        ]);
        const referral = referralSnap.data();
        const nowMs = Date.now();
        const finish = (fields) => {
            if (operationRef) {
                tx.update(operationRef, { ...fields, uid, updated_at: admin.firestore.FieldValue.serverTimestamp() });
            }
        };
        if (referral?.status === 'accepted' && referral.inviteeUid === uid) {
            finish({ status: 'completed', outcome: 'accepted' });
            return { accepted: true, inviterUid: referral.inviterUid, alreadyAccepted: true };
        }
        const refuse = (reason) => {
            finish({ status: 'completed', outcome: 'refused', reason });
            return { accepted: false, reason };
        };
        if (!referral)
            return refuse('referral_not_found');
        if (referral.inviterUid === uid)
            return refuse('self_referral');
        if (!inviteeReferrals.empty)
            return refuse('already_referred');
        if (isRegistryEntryActive(registrySnap, nowMs))
            return refuse('email_not_eligible');
        if (referral.status !== 'pending' || referral.inviteeUid)
            return refuse('referral_unavailable');
        const acceptedAt = admin.firestore.Timestamp.fromMillis(nowMs);
        // During an active referral game the ticket replaces the classic reward.
        const event = await prepareReferralReward(tx, referralRef.id, referral.inviterUid, acceptedAt);
        tx.create(pendingRef(referralRef.id), event);
        tx.update(referralRef, {
            ...(params.referralFields ?? {}),
            inviteeUid: uid,
            status: 'accepted',
            acceptedAt,
            rewardStatus: 'available',
            rewardType: 'all_games_until_midnight',
            rewardValue: 1,
            metadata: { ...(referral.metadata ?? {}), playerRewardRuleVersion: 2 },
        });
        tx.set((0, exports.emailRegistryRef)(emailKey), registryEntry('referred', nowMs));
        finish({ status: 'completed', outcome: 'accepted' });
        return { accepted: true, inviterUid: referral.inviterUid, alreadyAccepted: false };
    });
}
// --- Google ---------------------------------------------------------------------
// The Admin SDK cannot sign a user in. The public Auth REST endpoint used by
// the client SDKs can: called by the server with the Google ID token the app
// obtained, it creates the account if needed and reports isNewUser itself.
// The web API key is a public identifier (also shipped in the app); the
// Android key is restricted to the Android app and refuses server calls.
const kFirebaseWebApiKey = 'AIzaSyC5BmWaTrmSP09kn7soHgBwpPwyopbDleY';
// Unverified read of the token claims, only to key the operation and fail
// fast. Identity is established by signInWithIdp below, never by this.
function readUnverifiedGoogleClaims(idToken) {
    try {
        // The Auth emulator accepts an unsigned JSON token; a real JWT never
        // starts with "{" (Firebase rejects such a token in production anyway).
        const json = idToken.trimStart().startsWith('{') ? idToken :
            Buffer.from((idToken.split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
        const claims = JSON.parse(json);
        const sub = typeof claims.sub === 'string' ? claims.sub : '';
        const email = normalizeEmail(claims.email);
        return sub && email ? { sub, email } : null;
    }
    catch (_) {
        return null;
    }
}
async function signInWithGoogleIdToken(idToken) {
    const emulator = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const base = emulator ?
        `http://${emulator}/identitytoolkit.googleapis.com/v1` :
        'https://identitytoolkit.googleapis.com/v1';
    const key = emulator ? 'emulator-key' : kFirebaseWebApiKey;
    let response;
    try {
        response = await fetch(`${base}/accounts:signInWithIdp?key=${key}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
                requestUri: 'http://localhost',
                postBody: `id_token=${encodeURIComponent(idToken)}&providerId=google.com`,
                returnSecureToken: true,
            }),
        });
    }
    catch (_) {
        throw new functions.https.HttpsError('unavailable', 'Google sign-in unavailable.');
    }
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
        const message = String(body.error?.message ?? '');
        functions.logger.warn('REFERRAL_GOOGLE_IDP_REFUSED', { status: response.status, code: message.split(' ')[0] });
        if (response.status >= 500)
            throw new functions.https.HttpsError('unavailable', 'Google sign-in unavailable.');
        throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
    }
    const federatedId = typeof body.federatedId === 'string' ? body.federatedId : '';
    const uid = typeof body.localId === 'string' ? body.localId : '';
    const sub = federatedId.split('/').pop() || '';
    if (!uid || !sub)
        throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
    // The tokens returned for this server-side sign-in are discarded on purpose.
    return { isNewUser: body.isNewUser === true, uid, sub, email: normalizeEmail(body.email) };
}
const googleSignupRef = (sub) => firestore_1.db.collection('_referral_google_signups').doc(crypto.createHash('sha256').update(sub).digest('hex'));
exports.googleSignupRef = googleSignupRef;
async function authCreationMs(uid) {
    try {
        return Date.parse((await admin.auth().getUser(uid)).metadata.creationTime);
    }
    catch (_) {
        return NaN;
    }
}
// An account belongs to a signup operation if Firebase reported it new to
// this operation, or if it was created after the operation verified that no
// account existed for this Google identity (retry after a crash, or a
// concurrent sign-in of the same person). Auth creation times are rounded to
// the second, hence the margin of one second on a comparison that otherwise
// concerns a single event.
function accountBelongsToOperation(creationMs, checkedAbsentAtMs) {
    return Number.isFinite(creationMs) && creationMs >= Math.floor(checkedAbsentAtMs / 1000) * 1000 - 1000;
}
async function findGoogleAccount(identity) {
    for (const lookup of [
        () => admin.auth().getUserByProviderUid('google.com', identity.sub),
        () => admin.auth().getUserByEmail(identity.email),
    ]) {
        try {
            return await lookup();
        }
        catch (error) {
            if (error?.code !== 'auth/user-not-found') {
                throw new functions.https.HttpsError('unavailable', 'Account lookup unavailable.');
            }
        }
    }
    return null;
}
// --- Transition for app 1.1.1 -----------------------------------------------------
// App 1.1.1 creates the account itself, then sends the code. Accepted only
// while the transition is open: until 4 weeks after the real publication date
// of 1.1.2, entered by an admin in app_config/referral_signup once published.
// Without that date the transition stays open.
exports.kLegacyTransitionMs = 28 * 24 * 60 * 60 * 1000;
const referralSignupConfigRef = () => firestore_1.db.doc('app_config/referral_signup');
exports.referralSignupConfigRef = referralSignupConfigRef;
async function isLegacyTransitionOpen(nowMs) {
    const publishedAt = (await (0, exports.referralSignupConfigRef)().get()).get('app_1_1_2_published_at');
    if (publishedAt == null)
        return true;
    if (typeof publishedAt.toMillis !== 'function')
        return false; // Unreadable: closed.
    return nowMs < publishedAt.toMillis() + exports.kLegacyTransitionMs;
}
// Transition-only signal, not a proof: the session sending the code is the
// one that created the account (its sign-in time is the creation time). An
// existing account signing in again always has a later sign-in time.
function isAccountCreationSession(authTimeSeconds, creationMs) {
    const authTimeMs = Number(authTimeSeconds) * 1000;
    return Number.isFinite(authTimeMs) && Number.isFinite(creationMs) &&
        Math.abs(authTimeMs - creationMs) <= 1000;
}
