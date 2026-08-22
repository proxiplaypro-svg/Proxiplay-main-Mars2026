const admin = require("firebase-admin");
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

async function drawReferralGame(gameId, {allowEarly = false, now = admin.firestore.Timestamp.now()} = {}) {
  const gameRef = db.collection("referral_games").doc(gameId);
  return db.runTransaction(async (transaction) => {
    const gameSnap = await transaction.get(gameRef);
    if (!gameSnap.exists) throw new Error("Referral game not found.");
    const game = gameSnap.data() || {};
    if (["completed", "no_eligible_entries"].includes(text(game.draw_status))) {
      return {status: "already_finalized", winnerUid: text(game.winner_uid)};
    }
    if (game.status !== "active") throw new Error("Referral game is not active.");
    if (!allowEarly && (!game.end_date || game.end_date.toMillis() > now.toMillis())) {
      throw new Error("Referral game has not ended yet.");
    }
    const entriesSnap = await transaction.get(gameRef.collection("entries"));
    const eligible = [];
    for (const entryDoc of entriesSnap.docs) {
      const entry = entryDoc.data() || {};
      const inviterUid = text(entry.inviter_uid);
      const userRef = inviterUid ? db.collection("users").doc(inviterUid) : null;
      const userSnap = userRef ? await transaction.get(userRef) : null;
      if (!userRef || !userSnap.exists || excluded(userSnap.data() || {})) {
        transaction.set(entryDoc.ref, {eligibility_status: "excluded", updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
        continue;
      }
      eligible.push({...entry, inviter_uid: inviterUid, entryRef: entryDoc.ref, userRef});
    }
    if (eligible.length === 0) {
      transaction.set(gameRef, {
        status: "ended", draw_status: "no_eligible_entries", drawn_at: now,
        total_ticket_count: entriesSnap.size, eligible_ticket_count: 0,
      }, {merge: true});
      return {status: "no_eligible_entries", winnerUid: ""};
    }
    const selected = pickWinningTicket(eligible);
    const winnerRef = selected.winningTicket.userRef;
    const prizeRef = db.collection("prizes").doc(`referral_game_${gameId}`);
    const prizeSnap = await transaction.get(prizeRef);
    if (!prizeSnap.exists) transaction.set(prizeRef, prizePayload(gameId, game, winnerRef, now));
    transaction.set(winnerRef.collection("my_lots").doc(prizeRef.id), {
      prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(selected.winningTicket.entryRef, {
      eligibility_status: "won", drawn_at: now, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(gameRef, {
      status: "ended", draw_status: "completed", winner_uid: selected.winnerUid,
      winner_ref: winnerRef, winner_ticket_count: selected.winnerTicketCount,
      total_ticket_count: entriesSnap.size, eligible_ticket_count: eligible.length,
      drawn_at: now, prize_ref: prizeRef,
    }, {merge: true});
    return {status: "completed", winnerUid: selected.winnerUid, prizeId: prizeRef.id};
  });
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
    if (!winnerSnap.exists) throw new Error("Winner no longer exists.");
    const prizeRef = db.collection("prizes").doc(`referral_game_${gameId}`);
    const prizeSnap = await transaction.get(prizeRef);
    const drawnAt = game.drawn_at || admin.firestore.Timestamp.now();
    if (!prizeSnap.exists) transaction.set(prizeRef, prizePayload(gameId, game, winnerRef, drawnAt));
    transaction.set(winnerRef.collection("my_lots").doc(prizeRef.id), {
      prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(gameRef, {status: "ended", draw_status: "completed", winner_ref: winnerRef, prize_ref: prizeRef, drawn_at: drawnAt}, {merge: true});
    return {status: prizeSnap.exists ? "repaired_my_lots" : "repaired_prize_and_my_lots", prizeId: prizeRef.id};
  });
}

module.exports = {drawReferralGame, repairReferralGameDraw};
