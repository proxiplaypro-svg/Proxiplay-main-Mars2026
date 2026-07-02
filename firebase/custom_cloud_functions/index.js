const admin = require("firebase-admin/app");
admin.initializeApp();

const deleteEnseigneAndGames = require("./delete_enseigne_and_games.js");
exports.deleteEnseigneAndGames = deleteEnseigneAndGames.deleteEnseigneAndGames;
const deleteCommercantAccount = require("./delete_commercant_account.js");
exports.deleteCommercantAccount =
  deleteCommercantAccount.deleteCommercantAccount;
const backfillPlayerStatusCached = require("./backfill_player_status_cached.js");
exports.backfillPlayerStatusCached =
  backfillPlayerStatusCached.backfillPlayerStatusCached;
