// A single referral game may be active at a time, whoever activates it (Admin
// API, console, autoManageReferralGames, concurrent admin actions): the lock
// app_config/referral_game_active names the active game. It is maintained by
// enforceSingleActiveReferralGame (trigger on referral_games); a game made
// active while another one holds the lock is put back to draft.
//
// Acceptances read the lock to choose the game of a referral; without a
// usable lock, several active games give no game at all (classic reward),
// never a failed signup.
const admin = require("firebase-admin");
const functions = require("firebase-functions");

const db = admin.firestore();
const kLockPath = "app_config/referral_game_active";
const lockRef = () => db.doc(kLockPath);
const gameRef = (id) => db.doc(`referral_games/${id}`);

function coversDate(game, ms) {
  const start = game?.start_date?.toMillis?.();
  const end = game?.end_date?.toMillis?.();
  return game?.status === "active" && typeof start === "number" && typeof end === "number" &&
    start <= ms && ms <= end;
}

// Deterministic keeper among simultaneously active games: earliest start,
// then smallest id. Every concurrent run of the trigger agrees on it.
function keeperOf(docs) {
  return [...docs].sort((a, b) => {
    const d = (a.data().start_date?.toMillis?.() ?? Infinity) -
      (b.data().start_date?.toMillis?.() ?? Infinity);
    return d !== 0 ? d : a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  })[0];
}

// Within the acceptance transaction (reads only): the game a referral accepted
// at `acceptedAt` belongs to, or null for the classic reward.
async function selectReferralGameForAcceptance(tx, acceptedAt) {
  const ms = acceptedAt.toMillis();
  const holder = (await tx.get(lockRef())).data()?.game_id || null;
  if (holder) {
    const game = await tx.get(gameRef(holder));
    return game.exists && coversDate(game.data(), ms) ? game.id : null;
  }
  const active = (await tx.get(db.collection("referral_games").where("status", "==", "active")))
    .docs.filter((doc) => coversDate(doc.data(), ms));
  if (active.length > 1) {
    functions.logger.error("REFERRAL_GAME_MULTIPLE_ACTIVE", {ids: active.map((doc) => doc.id)});
    return null;
  }
  return active[0]?.id || null;
}

// Keeps the lock in line with the game just written. Idempotent; concurrent
// runs serialize on the lock document.
async function enforceSingleActiveReferralGame(gameId) {
  return db.runTransaction(async (tx) => {
    // All reads first (Firestore transactions).
    const [lockSnap, gameSnap, activeSnap] = await Promise.all([
      tx.get(lockRef()),
      tx.get(gameRef(gameId)),
      tx.get(db.collection("referral_games").where("status", "==", "active")),
    ]);
    const holder = lockSnap.data()?.game_id || null;
    const game = gameSnap.data();
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (game?.status !== "active") {
      if (holder === gameId) {
        tx.set(lockRef(), {game_id: null, released_at: now}, {merge: true});
        return {status: "released"};
      }
      return {status: "ignored"};
    }
    if (holder === gameId) return {status: "holder"};
    const holderActive = holder && activeSnap.docs.some((doc) => doc.id === holder);
    const keeper = holderActive ? holder : keeperOf(activeSnap.docs)?.id;
    if (keeper !== gameId) {
      tx.update(gameSnap.ref, {
        status: "draft",
        activation_refused_at: now,
        activation_refused_reason: "another_active_game",
        updated_at: now,
      });
      functions.logger.warn("REFERRAL_GAME_ACTIVATION_REFUSED", {gameId, activeGameId: keeper});
      return {status: "refused", activeGameId: keeper};
    }
    tx.set(lockRef(), {game_id: gameId, since: now}, {merge: true});
    return {status: "locked"};
  });
}

module.exports = {
  kLockPath,
  selectReferralGameForAcceptance,
  enforceSingleActiveReferralGame,
  coversDate,
};
