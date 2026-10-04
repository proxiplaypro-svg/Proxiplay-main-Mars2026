const {checkAwardLinks, review} = require("./prize_integrity");
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const crypto = require("crypto");
const {pickWinningTicket} = require("./lib/referral_games_core");

const db = admin.firestore();

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function excluded(userData) {
  if (!userData || userData.auto_deleted === true || userData.deleted === true) return true;
  const accountStatus = text(userData.account_status).toLowerCase();
  const playerStatus = text(userData.player_status_cached).toLowerCase();
  return ["rejected", "suspended"].includes(accountStatus) ||
    ["suspended", "suspendu"].includes(playerStatus);
}

function prizePayload(gameId, game, winnerRef, drawnAt) {
  const description = text(game.prize_description);
  return {
    prize_type: "referral_game",
    fulfillment_type: "platform",
    name: description || text(game.title) || "Lot parrainage",
    description,
    prize_label: description,
    winner_id: winnerRef,
    referral_game_id: gameId,
    claim_code: crypto.randomBytes(5).toString("hex").toUpperCase(),
    claimed: false,
    win_date: drawnAt,
    prize_value: Number.isFinite(Number(game.prize_value)) ? Number(game.prize_value) : 0,
  };
}

// "Phase 1/2/3" (meme principe que main_prize_draw.js apres l'incident
// Kids Troc) : avant ce correctif, le tirage faisait "for (const entryDoc
// of entriesSnap.docs) { await transaction.get(userRef) }" -- une lecture
// sequentielle par ticket, A L'INTERIEUR de la transaction (introduit par
// b1fdda3, 22/08/2026). Phase 1 fait ce travail HORS transaction, avec
// des lectures utilisateur batchees et deduppliquees par parrain (un
// meme inviter_uid peut detenir plusieurs tickets -- lu une seule fois,
// reutilise pour chacune de ses entrees : la ponderation par ticket
// n'est pas affectee puisque `eligible` conserve un element par TICKET,
// pas par parrain unique). Phase 3 ne relit que le jeu, le ticket
// candidat et le prize -- un cout constant quel que soit le nombre total
// de tickets.
const REFERRAL_PARTICIPANT_USER_BATCH_SIZE = 300;
// Borne explicite sur la boucle de repli de Phase 3 (ticket gagnant
// devenu inexclu/exclu entre Phase 1 et Phase 3) : garantit la
// terminaison sans jamais rescanner la collection entries.
const REFERRAL_MAX_CANDIDATE_ATTEMPTS = 20;

// Lecture batchee + deduplication par parrain. Fonctionne avec n'importe
// quel lecteur exposant getAll (Firestore nu en Phase 1, Transaction en
// Phase 3 pour la relecture bornee du ticket candidat).
async function loadEligibleReferralTickets(reader, entryDocs) {
  const entries = entryDocs.map((doc) => ({doc, inviterUid: text((doc.data() || {}).inviter_uid)}));
  const uniqueRefsByUid = new Map();
  for (const {inviterUid} of entries) {
    if (inviterUid && !uniqueRefsByUid.has(inviterUid)) uniqueRefsByUid.set(inviterUid, db.collection("users").doc(inviterUid));
  }
  const uniqueRefs = [...uniqueRefsByUid.values()];
  const snapshotByUid = new Map();
  for (let i = 0; i < uniqueRefs.length; i += REFERRAL_PARTICIPANT_USER_BATCH_SIZE) {
    const chunk = uniqueRefs.slice(i, i + REFERRAL_PARTICIPANT_USER_BATCH_SIZE);
    // eslint-disable-next-line no-await-in-loop
    const snaps = await reader.getAll(...chunk);
    for (const snap of snaps) snapshotByUid.set(snap.ref.id, snap);
  }
  const eligible = [];
  const excludedEntryRefs = [];
  for (const {doc: entryDoc, inviterUid} of entries) {
    const entry = entryDoc.data() || {};
    const userSnap = inviterUid ? snapshotByUid.get(inviterUid) : null;
    if (!inviterUid || !userSnap || !userSnap.exists || excluded(userSnap.data() || {})) {
      excludedEntryRefs.push(entryDoc.ref);
      continue;
    }
    eligible.push({...entry, inviter_uid: inviterUid, entryRef: entryDoc.ref, userRef: db.collection("users").doc(inviterUid)});
  }
  return {eligible, excludedEntryRefs};
}

function isReferralGameAlreadyFinalized(game) {
  return ["completed", "no_eligible_entries"].includes(text(game.draw_status));
}

async function drawReferralGame(gameId, {allowEarly = false, now = admin.firestore.Timestamp.now()} = {}) {
  const gameRef = db.collection("referral_games").doc(gameId);
  const t0 = Date.now();
  const step = (label) => functions.logger.info('DRAW_STEP_TIMING', {job: 'drawReferralGameWinner', gameId, step: label, elapsedMs: Date.now() - t0});

  // ---------------- Phase 1 : hors transaction ----------------
  const gameSnap = await gameRef.get();
  step('phase1_game_read');
  if (!gameSnap.exists) throw new Error("Referral game not found.");
  const game = gameSnap.data() || {};
  if (isReferralGameAlreadyFinalized(game)) {
    return {status: "already_finalized", winnerUid: text(game.winner_uid)};
  }
  if (!["active", "ended"].includes(game.status)) throw new Error("Referral game is not active.");
  if (!allowEarly && (!game.end_date || game.end_date.toMillis() > now.toMillis())) {
    throw new Error("Referral game has not ended yet.");
  }
  const pendingRewards = await db.collection('referral_reward_pending')
    .where('game_id', '==', gameId).where('status', 'in', ['pending', 'manual_review_required']).get();
  step('phase1_pending_rewards_query');
  if (!pendingRewards.empty) return review(gameId, 'unresolved_referral_rewards');

  const entriesSnap = await gameRef.collection("entries").get();
  step(`phase1_entries_read:count=${entriesSnap.docs.length}`);
  const {eligible, excludedEntryRefs} = await loadEligibleReferralTickets(db, entriesSnap.docs);
  step(`phase1_eligible_loaded:count=${eligible.length}`);

  // Marquage des tickets exclus : pure bookkeeping/audit, ne conditionne
  // jamais la selection (qui relit toujours l'etat live du compte), donc
  // sans danger a ecrire tot, hors transaction. Legere difference avec
  // l'ancien code : celui-ci ne marquait PAS ces tickets si checkAwardLinks
  // echouait ensuite (round sans finalisation) ; desormais ils le sont
  // quand meme -- le statut "exclu" reste exact independamment de l'issue
  // du tirage, et rien ne consomme ce champ pour la selection future.
  if (excludedEntryRefs.length > 0) {
    const batch = db.batch();
    for (const ref of excludedEntryRefs) {
      batch.set(ref, {eligibility_status: "excluded", updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    }
    await batch.commit();
    step(`phase1_excluded_marked:count=${excludedEntryRefs.length}`);
  }

  if (eligible.length === 0) {
    const result = await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(gameRef);
      if (!freshSnap.exists) throw new Error("Referral game not found.");
      const freshGame = freshSnap.data() || {};
      if (isReferralGameAlreadyFinalized(freshGame)) return {status: "already_finalized", winnerUid: text(freshGame.winner_uid)};
      transaction.set(gameRef, {
        status: "ended", draw_status: "no_eligible_entries", drawn_at: now,
        total_ticket_count: entriesSnap.size, eligible_ticket_count: 0,
      }, {merge: true});
      return {status: "no_eligible_entries", winnerUid: ""};
    });
    step(`phase1_short_circuit:${result.status}`);
    return result;
  }

  // ---------------- Phase 2 : selection pure, aucune I/O ----------------
  // Meme semantique probabiliste qu'avant : tirage uniforme sur `eligible`,
  // qui conserve un element par ticket (pickWinningTicket recompte ensuite
  // winnerTicketCount en filtrant par inviter_uid parmi le pool fourni).
  const initialSelection = pickWinningTicket(eligible);
  const initialPool = [initialSelection.winningTicket, ...eligible.filter((t) => t !== initialSelection.winningTicket)];

  // ---------------- Phase 3 : transaction courte, O(1) ----------------
  return db.runTransaction(async (transaction) => {
    step('phase3_attempt_start');
    const freshSnap = await transaction.get(gameRef);
    step('phase3_game_read');
    if (!freshSnap.exists) throw new Error("Referral game not found.");
    const freshGame = freshSnap.data() || {};
    if (isReferralGameAlreadyFinalized(freshGame)) return {status: "already_finalized", winnerUid: text(freshGame.winner_uid)};
    if (!["active", "ended"].includes(freshGame.status)) throw new Error("Referral game is not active.");
    if (!allowEarly && (!freshGame.end_date || freshGame.end_date.toMillis() > now.toMillis())) {
      throw new Error("Referral game has not ended yet.");
    }
    const freshPendingRewards = await transaction.get(db.collection('referral_reward_pending')
      .where('game_id', '==', gameId).where('status', 'in', ['pending', 'manual_review_required']));
    step('phase3_pending_rewards_query');
    if (!freshPendingRewards.empty) return review(gameId, 'unresolved_referral_rewards');

    let winningTicket = null;
    let pool = initialPool;
    let attempt = 0;
    const retryExcluded = [];
    for (; attempt < REFERRAL_MAX_CANDIDATE_ATTEMPTS && pool.length > 0; attempt += 1) {
      const candidate = attempt === 0 ? pool[0] : pool[crypto.randomInt(pool.length)];
      // eslint-disable-next-line no-await-in-loop
      const userSnap = await transaction.get(candidate.userRef);
      step(`phase3_candidate_read:attempt=${attempt}`);
      if (userSnap.exists && !excluded(userSnap.data() || {})) { winningTicket = candidate; break; }
      retryExcluded.push(candidate.entryRef);
      pool = pool.filter((t) => t.inviter_uid !== candidate.inviter_uid);
    }
    if (!winningTicket) {
      if (pool.length === 0) {
        for (const ref of retryExcluded) {
          transaction.set(ref, {eligibility_status: "excluded", updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
        }
        transaction.set(gameRef, {
          status: "ended", draw_status: "no_eligible_entries", drawn_at: now,
          total_ticket_count: entriesSnap.size, eligible_ticket_count: 0,
        }, {merge: true});
        return {status: "no_eligible_entries", winnerUid: ""};
      }
      functions.logger.warn('DRAW_CANDIDATE_RETRY_BUDGET_EXCEEDED', {job: 'drawReferralGameWinner', gameId, triedCount: attempt, untestedRemaining: pool.length});
      return {status: "retry_needed", reason: "candidate_retry_budget_exceeded"};
    }
    const winnerTicketCount = eligible.filter((t) => t.inviter_uid === winningTicket.inviter_uid).length;
    const winnerRef = winningTicket.userRef;
    const prizeRef = db.collection("prizes").doc(`referral_game_${gameId}`);
    const prizeSnap = await transaction.get(prizeRef);
    step('phase3_prize_read');
    const integrity = await checkAwardLinks(transaction, {prizeRef, winnerRef: winnerRef, sourceField: 'referral_game_id', sourceValue: gameId, prizeSnap});
    if (integrity.status !== 'consistent') return integrity;
    for (const ref of retryExcluded) {
      transaction.set(ref, {eligibility_status: "excluded", updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    }
    if (!prizeSnap.exists) transaction.set(prizeRef, prizePayload(gameId, freshGame, winnerRef, now));
    transaction.set(winnerRef.collection("my_lots").doc(prizeRef.id), {
      prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(winningTicket.entryRef, {
      eligibility_status: "won", drawn_at: now, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(gameRef, {
      status: "ended", draw_status: "completed", winner_uid: winningTicket.inviter_uid,
      winner_ref: winnerRef, winner_ticket_count: winnerTicketCount,
      total_ticket_count: entriesSnap.size, eligible_ticket_count: eligible.length,
      drawn_at: now, prize_ref: prizeRef,
    }, {merge: true});
    return {status: "completed", winnerUid: winningTicket.inviter_uid, prizeId: prizeRef.id};
  }).then((r) => { step(`phase3_settled:${r?.status || 'unknown'}`); return r; },
    (error) => { step(`phase3_failed:${error?.code || error?.message || 'unknown'}`); throw error; });
}

async function repairReferralGameDraw(gameId) {
  const gameRef = db.collection("referral_games").doc(gameId);
  return db.runTransaction(async (transaction) => {
    const gameSnap = await transaction.get(gameRef);
    if (!gameSnap.exists) throw new Error("Referral game not found.");
    const game = gameSnap.data() || {};
    const winnerUid = text(game.winner_uid);
    if (!winnerUid) return {status: "nothing_to_repair"};
    const winnerRef = db.collection("users").doc(winnerUid);
    const winnerSnap = await transaction.get(winnerRef);
    if (!winnerSnap.exists) return review(gameId, 'missing_winner_account');
    const prizeRef = db.collection("prizes").doc(`referral_game_${gameId}`);
    const prizeSnap = await transaction.get(prizeRef);
    const integrity = await checkAwardLinks(transaction, {prizeRef, winnerRef: winnerRef, sourceField: 'referral_game_id', sourceValue: gameId, prizeSnap});
    if (integrity.status !== 'consistent') return integrity;
    const drawnAt = game.drawn_at || admin.firestore.Timestamp.now();
    if (!prizeSnap.exists) transaction.set(prizeRef, prizePayload(gameId, game, winnerRef, drawnAt));
    transaction.set(winnerRef.collection("my_lots").doc(prizeRef.id), {
      prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(gameRef, {status: "ended", draw_status: "completed", winner_ref: winnerRef, prize_ref: prizeRef, drawn_at: drawnAt}, {merge: true});
    return {status: prizeSnap.exists ? "repaired_my_lots" : "repaired_prize_and_my_lots", prizeId: prizeRef.id};
  });
}

module.exports = {drawReferralGame, repairReferralGameDraw, loadEligibleReferralTickets, REFERRAL_MAX_CANDIDATE_ATTEMPTS};
