import * as admin from 'firebase-admin';
import { db, refs } from './firestore';
import { ReferralRecord } from './types';

// Jeu de parrainage : un tirage au sort admin, periode definie a la creation.
// Tant qu'aucun jeu n'est actif, le parrainage valide continue de donner la
// recompense classique (share_promo). Des qu'un jeu est actif, chaque
// parrainage valide cree un ticket a la place -- pas de plafond, un
// parrain qui valide plusieurs filleuls accumule plusieurs tickets et donc
// plus de chances au tirage (voir draw_referral_game_winner.js).
export interface ReferralGameRecord {
  title: string;
  description: string;
  prize_description: string;
  status: 'draft' | 'active' | 'ended';
  start_date: admin.firestore.Timestamp;
  end_date: admin.firestore.Timestamp;
  created_by: string;
  created_at?: admin.firestore.FieldValue | admin.firestore.Timestamp;
  winner_uid?: string | null;
  draw_status?: string | null;
}

const referralGamesCollection = () => db.collection('referral_games');

export async function findActiveReferralGame(
  now: admin.firestore.Timestamp = admin.firestore.Timestamp.now(),
): Promise<{ id: string; data: ReferralGameRecord } | null> {
  const snap = await referralGamesCollection()
    .where('status', '==', 'active')
    .get();

  const active = snap.docs.filter((doc) => {
    const data = doc.data() as ReferralGameRecord;
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
  if (active.length > 1) throw new Error('Multiple referral games are active simultaneously.');

  return { id: active[0].id, data: active[0].data() as ReferralGameRecord };
}

export async function addReferralGameTicket(
  gameId: string,
  referralId: string,
  now: admin.firestore.Timestamp = admin.firestore.Timestamp.now(),
): Promise<'created' | 'already_exists' | 'ineligible'> {
  const gameRef = referralGamesCollection().doc(gameId);
  const referralRef = refs.referral(referralId);
  const entryRef = gameRef.collection('entries').doc(referralId);
  return db.runTransaction(async (transaction) => {
    const [gameSnap, referralSnap, entrySnap] = await Promise.all([
      transaction.get(gameRef),
      transaction.get(referralRef),
      transaction.get(entryRef),
    ]);
    if (entrySnap.exists) return 'already_exists';
    if (!gameSnap.exists || !referralSnap.exists) return 'ineligible';
    const game = gameSnap.data() as ReferralGameRecord;
    const referral = referralSnap.data() as ReferralRecord;
    const startMs = game.start_date?.toMillis?.();
    const endMs = game.end_date?.toMillis?.();
    if (game.status !== 'active' || startMs == null || endMs == null || startMs > now.toMillis() || endMs < now.toMillis()) return 'ineligible';
    if (referral.status !== 'accepted' || !referral.inviterUid?.trim()) return 'ineligible';
    const inviterRef = refs.user(referral.inviterUid);
    const inviterSnap = await transaction.get(inviterRef);
    const inviter = inviterSnap.data() as Record<string, unknown> | undefined;
    const accountStatus = String(inviter?.account_status ?? '').trim().toLowerCase();
    const playerStatus = String(inviter?.player_status_cached ?? '').trim().toLowerCase();
    if (!inviterSnap.exists || inviter?.auto_deleted === true || inviter?.deleted === true || accountStatus === 'rejected' || accountStatus === 'suspended' || playerStatus === 'suspended' || playerStatus === 'suspendu') return 'ineligible';
    transaction.set(
      entryRef,
      {
        inviter_uid: referral.inviterUid,
        referral_id: referralId,
        inviter_ref: inviterRef,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      },
    );
    transaction.set(
      gameRef,
      { ticket_count: admin.firestore.FieldValue.increment(1) },
      { merge: true },
    );
    return 'created';
  });
}

export async function reconcileReferralGameTickets(gameId: string) {
  const gameSnap = await referralGamesCollection().doc(gameId).get();
  if (!gameSnap.exists) throw new Error('Referral game not found.');
  const game = gameSnap.data() as ReferralGameRecord;
  const startMs = game.start_date?.toMillis?.();
  const endMs = game.end_date?.toMillis?.();
  if (startMs == null || endMs == null) throw new Error('Referral game has invalid dates.');
  const acceptedSnap = await refs.referrals().where('status', '==', 'accepted').get();
  const results = { created: 0, already_exists: 0, ineligible: 0 };
  for (const referralDoc of acceptedSnap.docs) {
    const referral = referralDoc.data() as ReferralRecord;
    if (!referral.acceptedAt || referral.acceptedAt.toMillis() < startMs || referral.acceptedAt.toMillis() > endMs) continue;
    results[await addReferralGameTicket(gameId, referralDoc.id, referral.acceptedAt)] += 1;
  }
  return results;
}
