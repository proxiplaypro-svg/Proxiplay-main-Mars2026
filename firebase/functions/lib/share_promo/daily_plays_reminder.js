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
exports.remindUsersWithRemainingDailyPlays = exports.kDailyPlaysReminderMessage = void 0;
exports.shouldRemindDailyPlays = shouldRemindDailyPlays;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("./firestore");
const kNotificationsConfigPath = 'app_config/notifications';
const kDailyPlaysReminderPageSize = 300;
// Rappel unique (1.1.4) : distingue les parties du jour, perdues a minuit,
// des parties bonus, conservees (bonus_part). Envoye seulement aux joueurs
// qui ont encore des parties du jour (requete remaining_part > 0).
exports.kDailyPlaysReminderMessage = Object.freeze({
    title: 'Il vous reste des parties du jour !',
    body: 'Jouez-les avant minuit. Vos parties bonus, elles, sont conservées.',
});
// Comptes sans parties a jouer : jamais relances.
function shouldRemindDailyPlays(userData) {
    const remainingPart = Number(userData?.remaining_part);
    if (!Number.isFinite(remainingPart) || remainingPart <= 0)
        return false;
    const role = userData?.user_role;
    return role !== 'commercant' && role !== 'admin';
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
// Relance chaque joueur ayant encore des parties du jour (remaining_part > 0)
// non jouees le jour meme ; jamais les commercants ni les administrateurs. Paginee (curseur sur remaining_part + id document)
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
            if (!shouldRemindDailyPlays(userDoc.data())) {
                skippedWithoutParts += 1;
                continue;
            }
            try {
                await (0, firestore_1.queueUserPushNotification)({
                    docId: `daily_remaining_plays_${dateKey}_${userDoc.id}`,
                    title: exports.kDailyPlaysReminderMessage.title,
                    body: exports.kDailyPlaysReminderMessage.body,
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
