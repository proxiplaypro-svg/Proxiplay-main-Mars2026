import * as admin from 'firebase-admin';
import { db } from './firestore';

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
  if (active.length > 1) {
    console.warn(
      `[referral_games] ${active.length} jeux de parrainage actifs simultanement, utilisation du premier (${active[0].id}).`,
    );
  }

  return { id: active[0].id, data: active[0].data() as ReferralGameRecord };
}

export async function addReferralGameTicket(
  gameId: string,
  inviterUid: string,
  referralId: string,
): Promise<void> {
  const gameRef = referralGamesCollection().doc(gameId);
  await db.runTransaction(async (transaction) => {
    transaction.set(
      gameRef.collection('entries').doc(),
      {
        inviter_uid: inviterUid,
        referral_id: referralId,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      },
    );
    transaction.set(
      gameRef,
      { ticket_count: admin.firestore.FieldValue.increment(1) },
      { merge: true },
    );
  });
}
