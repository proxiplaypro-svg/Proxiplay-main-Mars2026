const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {runScheduledDraws} = require("./scheduled_draw_runner");
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

    return runScheduledDraws({
      name: "drawReferralGameWinner",
      logger: functions.logger,
      load: async () => {
        const gamesSnap = await db
          .collection("referral_games")
          .where("status", "in", ["active", "ended"])
          .where("end_date", "<=", now)
          .get();

        return gamesSnap.docs.filter(
          (doc) => !getTrimmedString((doc.data() || {}).winner_uid)
        );
      },
      draw: (doc) => drawReferralGame(doc.id, {now}),
    });
  });

exports.drawReferralGame = drawReferralGame;
exports.repairReferralGameDraw = repairReferralGameDraw;
