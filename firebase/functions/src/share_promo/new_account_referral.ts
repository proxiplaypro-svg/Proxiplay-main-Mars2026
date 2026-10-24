// A referral is only valid when it is attached to the creation of a new
// ProxiPlay account, by e-mail or by Google. Firebase Authentication itself is
// the judge of "new": the e-mail path creates the account server-side
// (createUser fails for a known address), the Google path asks the Auth REST
// endpoint accounts:signInWithIdp, whose isNewUser flag is set by Firebase.
// Nothing here relies on a time window.
const {prepareReferralReward, pendingRef} = require('../../referral_reward_queue');
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import { db } from './firestore';
import { ReferralRecord } from './types';

export function normalizeEmail(email: unknown): string {
  return typeof email === 'string' ? email.trim().toLowerCase() : '';
}

// --- Shared acceptance --------------------------------------------------------
export type NewAccountReferralOutcome =
  | { accepted: true; inviterUid: string; alreadyAccepted: boolean }
  | { accepted: false; reason: string };

// One transaction for every path: the same referral or invitee can never be
// rewarded twice, even under concurrent calls. A deleted then recreated
// account is a new account (accepted trade-off: its former lots and history
// are lost). A business refusal is
// returned (not thrown) so the operation record is updated atomically.
export async function acceptReferralForNewAccount(params: {
  referralRef: FirebaseFirestore.DocumentReference;
  uid: string;
  operationRef?: FirebaseFirestore.DocumentReference;
  referralFields?: Record<string, unknown>;
}): Promise<NewAccountReferralOutcome> {
  const {referralRef, uid, operationRef} = params;
  return db.runTransaction(async (tx) => {
    const [referralSnap, inviteeReferrals] = await Promise.all([
      tx.get(referralRef),
      tx.get(db.collection('referrals').where('inviteeUid', '==', uid).limit(1)),
    ]);
    const referral = referralSnap.data() as ReferralRecord | undefined;
    const nowMs = Date.now();
    const finish = (fields: Record<string, unknown>) => {
      if (operationRef) {
        tx.update(operationRef, {...fields, uid, updated_at: admin.firestore.FieldValue.serverTimestamp()});
      }
    };
    if (referral?.status === 'accepted' && referral.inviteeUid === uid) {
      finish({status: 'completed', outcome: 'accepted'});
      return {accepted: true as const, inviterUid: referral.inviterUid, alreadyAccepted: true};
    }
    const refuse = (reason: string) => {
      finish({status: 'completed', outcome: 'refused', reason});
      return {accepted: false as const, reason};
    };
    if (!referral) return refuse('referral_not_found');
    if (referral.inviterUid === uid) return refuse('self_referral');
    if (!inviteeReferrals.empty) return refuse('already_referred');
    if (referral.status !== 'pending' || referral.inviteeUid) return refuse('referral_unavailable');

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
      metadata: {...(referral.metadata ?? {}), playerRewardRuleVersion: 2},
    });
    finish({status: 'completed', outcome: 'accepted'});
    return {accepted: true as const, inviterUid: referral.inviterUid, alreadyAccepted: false};
  });
}

// --- Google ---------------------------------------------------------------------
// The Admin SDK cannot sign a user in. The public Auth REST endpoint used by
// the client SDKs can: called by the server with the Google ID token the app
// obtained, it creates the account if needed and reports isNewUser itself.
// The web API key is a public identifier (also shipped in the app); the
// Android key is restricted to the Android app and refuses server calls.
const kFirebaseWebApiKey = 'AIzaSyC5BmWaTrmSP09kn7soHgBwpPwyopbDleY';

export interface GoogleIdentity {
  sub: string;
  email: string;
}

// Unverified read of the token claims, only to key the operation and fail
// fast. Identity is established by signInWithIdp below, never by this.
export function readUnverifiedGoogleClaims(idToken: string): GoogleIdentity | null {
  try {
    // The Auth emulator accepts an unsigned JSON token; a real JWT never
    // starts with "{" (Firebase rejects such a token in production anyway).
    const json = idToken.trimStart().startsWith('{') ? idToken :
      Buffer.from((idToken.split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    const claims = JSON.parse(json);
    const sub = typeof claims.sub === 'string' ? claims.sub : '';
    const email = normalizeEmail(claims.email);
    return sub && email ? {sub, email} : null;
  } catch (_) {
    return null;
  }
}

// OAuth clients of the ProxiPlay app (public identifiers, from
// google-services.json and GoogleService-Info.plist): the web client is the
// audience of the Android app's Google ID token, the iOS client that of iOS.
export const kGoogleIdTokenAudiences = [
  '337086897094-49ng00g9hh5iecvmui6b7fc10qmvodot.apps.googleusercontent.com',
  '337086897094-eclbdgjvlqu5bu0k5mbfa4bdljn7f0k2.apps.googleusercontent.com',
];
const kGoogleIssuers = ['accounts.google.com', 'https://accounts.google.com'];
let googleAuthClient: any = null;

const isDemoEmulator = (): boolean => !!process.env.FIREBASE_AUTH_EMULATOR_HOST &&
  String(process.env.GCLOUD_PROJECT || '').startsWith('demo-');

// Identity of an authentic Google ID token: Google signature, issuer,
// audience, expiry and verified address. Null when any check fails; thrown
// 'unavailable' when Google's keys cannot be fetched. Nothing is looked up
// before this. Only the isolated demo emulators (emulator host and demo-
// project) accept the unsigned JSON token of the Auth emulator. `certs`
// (key id -> PEM) replaces Google's published keys in tests. Error messages
// contain the token: never logged.
export async function verifyGoogleIdToken(
  idToken: string,
  certs?: Record<string, string>,
): Promise<GoogleIdentity | null> {
  if (isDemoEmulator() && idToken.trimStart().startsWith('{')) {
    const claims = readUnverifiedGoogleClaims(idToken);
    return claims && JSON.parse(idToken).email_verified === true ? claims : null;
  }
  if (!googleAuthClient) {
    const {OAuth2Client} = require('google-auth-library');
    googleAuthClient = new OAuth2Client();
  }
  let keys = certs;
  if (!keys) {
    try {
      keys = (await googleAuthClient.getFederatedSignonCertsAsync()).certs as Record<string, string>;
    } catch (_) {
      throw new functions.https.HttpsError('unavailable', 'Google sign-in unavailable.');
    }
  }
  try {
    const ticket = await googleAuthClient.verifySignedJwtWithCertsAsync(
      idToken, keys, kGoogleIdTokenAudiences, kGoogleIssuers);
    const payload = ticket.getPayload() ?? {};
    const sub = typeof payload.sub === 'string' ? payload.sub : '';
    const email = normalizeEmail(payload.email);
    return sub && email && payload.email_verified === true ? {sub, email} : null;
  } catch (_) {
    return null;
  }
}

export interface IdpSignInResult {
  isNewUser: boolean;
  uid: string;
  sub: string;
  email: string;
}

export async function signInWithGoogleIdToken(idToken: string): Promise<IdpSignInResult> {
  const emulator = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const base = emulator ?
    `http://${emulator}/identitytoolkit.googleapis.com/v1` :
    'https://identitytoolkit.googleapis.com/v1';
  const key = emulator ? 'emulator-key' : kFirebaseWebApiKey;
  let response: Response;
  try {
    response = await fetch(`${base}/accounts:signInWithIdp?key=${key}`, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        requestUri: 'http://localhost',
        postBody: `id_token=${encodeURIComponent(idToken)}&providerId=google.com`,
        returnSecureToken: true,
      }),
    });
  } catch (_) {
    throw new functions.https.HttpsError('unavailable', 'Google sign-in unavailable.');
  }
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) {
    const message = String((body.error as {message?: unknown} | undefined)?.message ?? '');
    functions.logger.warn('REFERRAL_GOOGLE_IDP_REFUSED', {status: response.status, code: message.split(' ')[0]});
    if (response.status >= 500) throw new functions.https.HttpsError('unavailable', 'Google sign-in unavailable.');
    throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
  }
  const federatedId = typeof body.federatedId === 'string' ? body.federatedId : '';
  const uid = typeof body.localId === 'string' ? body.localId : '';
  const sub = federatedId.split('/').pop() || '';
  if (!uid || !sub) throw new functions.https.HttpsError('unauthenticated', 'Invalid Google sign-in.');
  // The tokens returned for this server-side sign-in are discarded on purpose.
  return {isNewUser: body.isNewUser === true, uid, sub, email: normalizeEmail(body.email)};
}

export const googleSignupRef = (sub: string) =>
  db.collection('_referral_google_signups').doc(crypto.createHash('sha256').update(sub).digest('hex'));

export async function authCreationMs(uid: string): Promise<number> {
  try {
    return Date.parse((await admin.auth().getUser(uid)).metadata.creationTime);
  } catch (_) {
    return NaN;
  }
}

// An account belongs to a signup operation if Firebase reported it new to
// this operation, or if it was created after the operation verified that no
// account existed for this Google identity (retry after a crash, or a
// concurrent sign-in of the same person). Auth creation times are rounded to
// the second, hence the margin of one second on a comparison that otherwise
// concerns a single event.
export function accountBelongsToOperation(creationMs: number, checkedAbsentAtMs: number): boolean {
  return Number.isFinite(creationMs) && creationMs >= Math.floor(checkedAbsentAtMs / 1000) * 1000 - 1000;
}

export async function findGoogleAccount(identity: GoogleIdentity): Promise<admin.auth.UserRecord | null> {
  for (const lookup of [
    () => admin.auth().getUserByProviderUid('google.com', identity.sub),
    () => admin.auth().getUserByEmail(identity.email),
  ]) {
    try {
      return await lookup();
    } catch (error: any) {
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
export const kLegacyTransitionMs = 28 * 24 * 60 * 60 * 1000;
export const referralSignupConfigRef = () => db.doc('app_config/referral_signup');

export async function isLegacyTransitionOpen(nowMs: number): Promise<boolean> {
  const publishedAt = (await referralSignupConfigRef().get()).get('app_1_1_2_published_at');
  if (publishedAt == null) return true;
  if (typeof publishedAt.toMillis !== 'function') return false; // Unreadable: closed.
  return nowMs < publishedAt.toMillis() + kLegacyTransitionMs;
}

// Transition-only signal, not a proof: the session sending the code is the
// one that created the account (its sign-in time is the creation time). An
// existing account signing in again always has a later sign-in time.
export function isAccountCreationSession(authTimeSeconds: unknown, creationMs: number): boolean {
  const authTimeMs = Number(authTimeSeconds) * 1000;
  return Number.isFinite(authTimeMs) && Number.isFinite(creationMs) &&
    Math.abs(authTimeMs - creationMs) <= 1000;
}
