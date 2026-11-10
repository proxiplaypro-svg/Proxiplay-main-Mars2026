#!/usr/bin/env node
// Envoi UNIQUE de la notification « Vos parties bonus ne disparaissent
// plus ! » (1.1.4). A lancer a la main, apres publication sur les stores.
//
// Par defaut : simulation, rien n'est ecrit (affiche le document prevu).
// Ecriture : --apply --confirm --project=<id> --players-group-deployed
//   --players-group-deployed atteste que sendPushNotificationsTrigger en
//   production connait le groupe "Players" ; sinon l'ancienne version
//   enverrait a tout le monde (commercants et administrateurs compris).
// Un second lancement ne renvoie rien : identifiant de document fixe.
// Voir docs/bonus-reserve-announcement-1.1.4.md.
const admin = require("firebase-admin");
const {
  buildBonusReserveAnnouncementRequest,
  kBonusReserveAnnouncementDocId,
  queueBonusReserveAnnouncement,
} = require("../bonus_reserve_announcement");

function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  const value = (name) => {
    const arg = argv.find((entry) => entry.startsWith(`${name}=`));
    return arg ? arg.slice(name.length + 1) : "";
  };
  return {
    apply: flags.has("--apply"),
    confirm: flags.has("--confirm"),
    playersGroupDeployed: flags.has("--players-group-deployed"),
    projectId: value("--project"),
    createdBy: value("--created-by"),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const preview = buildBonusReserveAnnouncementRequest({createdBy: args.createdBy});
  console.log(`Document prevu : ff_push_notifications/${kBonusReserveAnnouncementDocId}`);
  console.log(JSON.stringify({...preview, created_at: "<serverTimestamp>"}, null, 2));

  if (!args.apply) {
    console.log("Simulation : rien n'a ete ecrit. Ajoutez --apply --confirm pour envoyer.");
    return;
  }
  if (!args.confirm || !args.projectId || !args.playersGroupDeployed) {
    throw new Error(
      "--apply exige --confirm, --project=<id> et --players-group-deployed.",
    );
  }

  admin.initializeApp({projectId: args.projectId});
  const result = await queueBonusReserveAnnouncement(admin.firestore(), {
    createdBy: args.createdBy,
  });
  console.log(result.status === "queued"
    ? `Notification mise en file : ${result.path}`
    : `Deja envoyee (${result.path}) : rien n'a ete renvoye.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
