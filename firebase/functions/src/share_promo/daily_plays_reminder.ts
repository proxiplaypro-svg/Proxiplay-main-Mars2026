import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { db, queueUserPushNotification, region } from './firestore';

const kNotificationsConfigPath = 'app_config/notifications';
const kDailyPlaysReminderPageSize = 300;

// Rappel unique (1.1.4) : distingue les parties du jour, perdues a minuit,
// des parties bonus, conservees (bonus_part). Envoye seulement aux joueurs
// qui ont encore des parties du jour (requete remaining_part > 0).
export const kDailyPlaysReminderMessage = Object.freeze({
  title: 'Il vous reste des parties du jour !',
  body: 'Jouez-les avant minuit. Vos parties bonus, elles, sont conservées.',
});

// Comptes sans parties a jouer : jamais relances.
export function shouldRemindDailyPlays(userData: FirebaseFirestore.DocumentData | undefined): boolean {
  const remainingPart = Number(userData?.remaining_part);
  if (!Number.isFinite(remainingPart) || remainingPart <= 0) return false;
  const role = userData?.user_role;
  return role !== 'commercant' && role !== 'admin';
}

function getParisDateKey(date: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Paris',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

async function isDailyRemainingChancesReminderEnabled(): Promise<boolean> {
  const snap = await db.doc(kNotificationsConfigPath).get();
  const data = (snap.exists ? snap.data() : undefined) ?? {};
  return (
    (data as { dailyRemainingChancesReminderEnabled?: unknown })
      .dailyRemainingChancesReminderEnabled !== false
  );
}

// Relance chaque joueur ayant encore des parties du jour (remaining_part > 0)
// non jouees le jour meme ; jamais les commercants ni les administrateurs. Paginee (curseur sur remaining_part + id document)
// pour ne jamais depasser le timeout -- contrairement a l'ancienne version
// (boucle non paginee sur tous les utilisateurs avec remaining_part > 0,
// qui timeoutait systematiquement passe un certain volume d'utilisateurs,
// laissant silencieusement de cote les utilisateurs les plus loin dans le
// tri par defaut).
export const remindUsersWithRemainingDailyPlays = functions
  .region(region)
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 18 * * *')
  .timeZone('Europe/Paris')
  .onRun(async () => {
    if (!(await isDailyRemainingChancesReminderEnabled())) {
      functions.logger.info(
        '[remindUsersWithRemainingDailyPlays] skipped: disabled in app_config/notifications',
      );
      return null;
    }

    const dateKey = getParisDateKey();
    let lastDocSnapshot: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    let pageCount = 0;
    let scanned = 0;
    let queued = 0;
    let skippedWithoutParts = 0;
    let failed = 0;

    // eslint-disable-next-line no-constant-condition
    while (true) {
      let query = db
        .collection('users')
        .where('remaining_part', '>', 0)
        .orderBy('remaining_part')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(kDailyPlaysReminderPageSize) as FirebaseFirestore.Query;

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
          await queueUserPushNotification({
            docId: `daily_remaining_plays_${dateKey}_${userDoc.id}`,
            title: kDailyPlaysReminderMessage.title,
            body: kDailyPlaysReminderMessage.body,
            userUid: userDoc.id,
            createdBy: 'system/remindUsersWithRemainingDailyPlays',
          });
          queued += 1;
        } catch (error) {
          failed += 1;
          functions.logger.error(
            `[remindUsersWithRemainingDailyPlays] user=${userDoc.id} error=${
              (error as Error).message || error
            }`,
          );
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
