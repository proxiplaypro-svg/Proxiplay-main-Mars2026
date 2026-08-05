"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.remindUsersWithRemainingDailyPlays = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("./firestore");
const kNotificationsConfigPath = 'app_config/notifications';
const kDailyPlaysReminderPageSize = 300;
const dailyPlaysReminderVariants = [
    { title: 'Il vous reste des chances !', body: 'Tentez votre chance avant minuit.' },
    { title: 'Vos parties du jour vous attendent', body: "Vous avez encore des chances à jouer aujourd'hui." },
    { title: 'Ne laissez pas vos parties expirer', body: 'Utilisez vos chances avant la fin de la journée.' },
    { title: 'Des jeux vous attendent encore', body: "Vous pouvez encore jouer sur ProxiPlay aujourd'hui." },
    { title: 'Il est encore temps de jouer', body: 'Vos chances du jour ne sont pas encore utilisées.' },
    { title: "Vous n'avez pas tout utilisé", body: 'Revenez tenter votre chance avant minuit.' },
    { title: 'Encore des chances disponibles', body: "Profitez-en tant qu'il est encore temps." },
    { title: "Votre journée ProxiPlay n'est pas finie", body: 'Il vous reste encore des parties à jouer.' },
];
function pickRandomVariant() {
    const index = Math.floor(Math.random() * dailyPlaysReminderVariants.length);
    return dailyPlaysReminderVariants[index];
}
function getParisDateKey(date = new Date()) {
    return new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Paris',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(date);
}
async function isDailyRemainingChancesReminderEnabled() {
    const snap = await firestore_1.db.doc(kNotificationsConfigPath).get();
    const data = (snap.exists ? snap.data() : undefined) ?? {};
    return (data
        .dailyRemainingChancesReminderEnabled !== false);
}
// Relance chaque joueur ayant encore des chances (remaining_part > 0) non
// jouees le jour meme. Paginee (curseur sur remaining_part + id document)
// pour ne jamais depasser le timeout -- contrairement a l'ancienne version
// (boucle non paginee sur tous les utilisateurs avec remaining_part > 0,
// qui timeoutait systematiquement passe un certain volume d'utilisateurs,
// laissant silencieusement de cote les utilisateurs les plus loin dans le
// tri par defaut).
exports.remindUsersWithRemainingDailyPlays = functions
    .region(firestore_1.region)
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule('0 18 * * *')
    .timeZone('Europe/Paris')
    .onRun(async () => {
    if (!(await isDailyRemainingChancesReminderEnabled())) {
        functions.logger.info('[remindUsersWithRemainingDailyPlays] skipped: disabled in app_config/notifications');
        return null;
    }
    const dateKey = getParisDateKey();
    let lastDocSnapshot = null;
    let pageCount = 0;
    let scanned = 0;
    let queued = 0;
    let skippedWithoutParts = 0;
    let failed = 0;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let query = firestore_1.db
            .collection('users')
            .where('remaining_part', '>', 0)
            .orderBy('remaining_part')
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(kDailyPlaysReminderPageSize);
        if (lastDocSnapshot) {
            query = query.startAfter(lastDocSnapshot);
        }
        const usersSnap = await query.get();
        if (usersSnap.empty) {
            break;
        }
        const docs = usersSnap.docs;
        lastDocSnapshot = docs[docs.length - 1];
        pageCount += 1;
        for (const userDoc of docs) {
            scanned += 1;
            const remainingPart = Number(userDoc.get('remaining_part'));
            if (!Number.isFinite(remainingPart) || remainingPart <= 0) {
                skippedWithoutParts += 1;
                continue;
            }
            const variant = pickRandomVariant();
            try {
                await (0, firestore_1.queueUserPushNotification)({
                    docId: `daily_remaining_plays_${dateKey}_${userDoc.id}`,
                    title: variant.title,
                    body: variant.body,
                    userUid: userDoc.id,
                    createdBy: 'system/remindUsersWithRemainingDailyPlays',
                });
                queued += 1;
            }
            catch (error) {
                failed += 1;
                functions.logger.error(`[remindUsersWithRemainingDailyPlays] user=${userDoc.id} error=${error.message || error}`);
            }
        }
    }
    functions.logger.info('[remindUsersWithRemainingDailyPlays] done', {
        dateKey,
        pageCount,
        scanned,
        queued,
        skippedWithoutParts,
        failed,
    });
    return null;
});
