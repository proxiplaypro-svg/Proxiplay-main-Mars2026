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
//
// runWith/concurrency/timeBudgetMs ajoutes avec la restructuration Phase
// 1/2/3 de drawReferralGame (referral_game_engine.js), par coherence avec
// pickMainPrizeWinners qui avait besoin exactement de la meme marge pour
// la meme raison. Avant ce changement, cette fonction n'avait AUCUN
// runWith() explicite (limites Gen1 par defaut : 60s/256MB -- le timeout
// le plus court de toute la famille de moteurs de tirage) et tournait en
// serie stricte sans budget de temps : un seul jeu de parrainage bloque
// (ex. beaucoup de tickets en boucle de repli) aurait empeche tous les
// suivants d'etre meme tentes avant le timeout de l'invocation entiere.
exports.drawReferralGameWinner = functions.runWith({timeoutSeconds: 300, memory: "1GB"}).pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    return runScheduledDraws({
      name: "drawReferralGameWinner",
      logger: functions.logger,
      concurrency: 8,
      timeBudgetMs: 270000,
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
