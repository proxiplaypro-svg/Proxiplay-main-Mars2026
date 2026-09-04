const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { drawReferralGame, repairReferralGameDraw } = require("./referral_game_engine");

const db = admin.firestore();

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

// Tourne chaque nuit a minuit (Europe/Paris). Meme moteur de tirage
// (drawReferralGame, dans referral_game_engine.js) que les autres types de
// jeux : filtrage des comptes exclus, tirage sous transaction, creation du
// prize. La notification du gagnant part ensuite automatiquement via le
// trigger onCreate generique notifyPrizeWon sur prizes/{prizeId}.
// Traite tous les jeux de parrainage "active" dont end_date est passee et
// sans gagnant.
exports.drawReferralGameWinner = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const gamesSnap = await db
      .collection("referral_games")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();

    const eligible = gamesSnap.docs.filter(
      (doc) => !getTrimmedString((doc.data() || {}).winner_uid)
    );

    functions.logger.info("drawReferralGameWinner: run started", {
      total: gamesSnap.size,
      eligible: eligible.length,
    });

    for (const doc of eligible) {
      try {
        await drawReferralGame(doc.id);
      } catch (error) {
        functions.logger.error(
          `drawReferralGameWinner: failed for gameId=${doc.id}`,
          error
        );
      }
    }

    return null;
  });

exports.drawReferralGame = drawReferralGame;
exports.repairReferralGameDraw = repairReferralGameDraw;
