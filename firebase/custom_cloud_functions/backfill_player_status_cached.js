const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();

/**
 * Calcule le statut du joueur basé sur son activité réelle.
 * 
 * Règles :
 * - actif: dernière activité <= 7 jours OU (dernier <= 14 jours ET games_played >= 3)
 * - a_relancer: dernier 8-30 jours OU (compte > 7 jours ET games_played <= 2)
 * - dormant: dernier 31-90 jours OU (compte > 30 jours ET games_played <= 1)
 * - mort_probable: dernier > 90 jours OU (compte > 60 jours ET 0 participation)
 * - statut_inconnu: données manquantes ou incohérentes
 * 
 * @param userData - Document utilisateur avec created_time, last_real_activity_at, games_played_count
 * @param now - Timestamp serveur actuel
 * @returns {string} - Un des statuts ci-dessus
 */
function calculatePlayerStatus(userData, now) {
  // Vérifier les données requises
  if (!userData || !userData.created_time) {
    return 'statut_inconnu';
  }

  const createdTime = userData.created_time;
  const lastActivityAt = userData.last_real_activity_at;
  const gamesPlayed = userData.games_played_count || 0;

  // Convertir les timestamps Firestore en millisecondes
  const nowMs = now.toMillis ? now.toMillis() : now;
  const createdMs = createdTime.toMillis ? createdTime.toMillis() : createdTime;
  const lastActivityMs = lastActivityAt
    ? (lastActivityAt.toMillis ? lastActivityAt.toMillis() : lastActivityAt)
    : null;

  // Calculer les délais en jours
  const accountAgeDays = Math.floor((nowMs - createdMs) / (1000 * 60 * 60 * 24));
  const daysSinceActivity = lastActivityMs
    ? Math.floor((nowMs - lastActivityMs) / (1000 * 60 * 60 * 24))
    : null;

  // Règle 1 : ACTIF
  if (lastActivityMs !== null) {
    if (daysSinceActivity <= 7) {
      return 'actif';
    }
    if (daysSinceActivity <= 14 && gamesPlayed >= 3) {
      return 'actif';
    }
  }

  // Règle 2 : À RELANCER
  if (lastActivityMs !== null && daysSinceActivity >= 8 && daysSinceActivity <= 30) {
    return 'a_relancer';
  }
  if (accountAgeDays > 7 && gamesPlayed <= 2) {
    return 'a_relancer';
  }

  // Règle 3 : DORMANT
  if (lastActivityMs !== null && daysSinceActivity >= 31 && daysSinceActivity <= 90) {
    return 'dormant';
  }
  if (accountAgeDays > 30 && gamesPlayed <= 1) {
    return 'dormant';
  }

  // Règle 4 : MORT PROBABLE
  if (accountAgeDays > 60 && gamesPlayed === 0) {
    return 'mort_probable';
  }
  if (lastActivityMs !== null && daysSinceActivity > 90) {
    return 'mort_probable';
  }

  // Par défaut
  return 'statut_inconnu';
}

/**
 * Backfill idempotent et sûr pour la collection `users`.
 * Remplit uniquement le champ `player_status_cached` pour les users qui ne l'ont pas.
 * 
 * Contraintes respectées :
 * - Ne pas écraser les valeurs existantes
 * - Ne pas modifier `lastInactiveRelaunchAt` et `allGamesAccessUntil`
 * - Ne pas inventer de données
 * - Code idempotent et relançable sans danger
 * 
 * Paramètres optionnels:
 * - dryRun: boolean (défaut: false) - Simule sans écrire
 * - pageSize: number (défaut: 200, max: 300)
 * - maxPages: number (défaut: 10, max: 200)
 */
exports.backfillPlayerStatusCached = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    // Vérification d'authentification et d'autorisation admin
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez être authentifié."
      );
    }

    try {
      // Vérifier si l'utilisateur est admin
      await assertIsAdmin(context.auth.uid);
    } catch (e) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Accès admin requis."
      );
    }

    // Parser les paramètres
    const dryRun = toBoolean(data && data.dryRun, false);
    const pageSizeInput = Number(data && data.pageSize);
    const maxPagesInput = Number(data && data.maxPages);

    const pageSize = Math.max(
      1,
      Math.min(300, Number.isFinite(pageSizeInput) ? Math.trunc(pageSizeInput) : 200)
    );
    const maxPages = Math.max(
      1,
      Math.min(200, Number.isFinite(maxPagesInput) ? Math.trunc(maxPagesInput) : 10)
    );

    console.log(
      `[backfillPlayerStatusCached] STARTING (dryRun=${dryRun}, pageSize=${pageSize}, maxPages=${maxPages})`
    );

    let pageCount = 0;
    let totalScanned = 0;
    let totalUpdated = 0;
    let totalIgnored = 0;
    let totalErrors = 0;
    const errors = [];
    let lastDocSnapshot = null;

    try {
      const now = admin.firestore.Timestamp.now();

      // Boucle de pagination
      for (pageCount = 0; pageCount < maxPages; pageCount++) {
        let query = db
          .collection("users")
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(pageSize);

        // Si on a un dernier doc de la page précédente, continuer depuis celui-ci
        if (lastDocSnapshot) {
          query = query.startAfter(lastDocSnapshot);
        }

        const usersSnap = await query.get();

        if (usersSnap.empty) {
          console.log(`[backfillPlayerStatusCached] Page ${pageCount}: aucun document, arrêt.`);
          break;
        }

        const docs = usersSnap.docs;
        lastDocSnapshot = docs[docs.length - 1];

        console.log(
          `[backfillPlayerStatusCached] Page ${pageCount}: ${docs.length} documents`
        );

        // Traiter chaque document
        for (const userDoc of docs) {
          const uid = userDoc.id;
          const userData = userDoc.data() || {};

          totalScanned++;

          // Vérification d'idempotence: si le champ existe déjà, ne pas toucher
          if (userData.player_status_cached !== undefined && userData.player_status_cached !== null) {
            totalIgnored++;
            console.log(
              `[backfillPlayerStatusCached] SKIP ${uid}: player_status_cached=${userData.player_status_cached} (existe)`
            );
            continue;
          }

          // Calcul du nouveau statut
          let newStatus = 'statut_inconnu';
          try {
            newStatus = calculatePlayerStatus(userData, now);
          } catch (err) {
            totalErrors++;
            const errMsg = `[backfillPlayerStatusCached] ERROR ${uid}: calcul échoué: ${err.message}`;
            console.error(errMsg);
            errors.push({ uid, error: err.message });
            continue;
          }

          // En dry-run, ne pas écrire
          if (dryRun) {
            totalUpdated++;
            console.log(
              `[backfillPlayerStatusCached] DRY-RUN UPDATE ${uid}: player_status_cached=${newStatus}`
            );
            continue;
          }

          // Écriture atomique avec merge=true (idempotent)
          try {
            await userDoc.ref.update({
              player_status_cached: newStatus
            });
            totalUpdated++;
            console.log(
              `[backfillPlayerStatusCached] UPDATE ${uid}: player_status_cached=${newStatus}`
            );
          } catch (err) {
            totalErrors++;
            const errMsg = `[backfillPlayerStatusCached] ERROR ${uid}: écriture échouée: ${err.message}`;
            console.error(errMsg);
            errors.push({ uid, error: `Update failed: ${err.message}` });
          }
        }
      }

      const summary = {
        dryRun,
        pageSize,
        maxPages,
        pagesProcessed: pageCount,
        totalScanned,
        totalUpdated,
        totalIgnored,
        totalErrors,
        success: totalErrors === 0,
        errors: errors.slice(0, 10), // Limiter à 10 premiers erreurs
        timestamp: new Date().toISOString(),
      };

      console.log(
        `[backfillPlayerStatusCached] COMPLETED: ${totalScanned} scannés, ${totalUpdated} mis à jour, ${totalIgnored} ignorés, ${totalErrors} erreurs`
      );

      return summary;
    } catch (err) {
      console.error(
        `[backfillPlayerStatusCached] CRITICAL ERROR: ${err.message}`
      );
      throw new functions.https.HttpsError(
        "internal",
        `Backfill échoué: ${err.message}`
      );
    }
  });

/**
 * Fonction auxiliaire pour vérifier si un utilisateur est admin
 */
async function assertIsAdmin(uid) {
  const userSnap = await db.doc(`users/${uid}`).get();
  const role = (userSnap.exists && userSnap.data().user_role) || "";
  if (role !== "admin") {
    throw new Error("permission-denied: admin required");
  }
}

/**
 * Fonction auxiliaire pour parser un booléen
 */
function toBoolean(value, defaultValue = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const lower = value.toLowerCase().trim();
    return lower === "true" || lower === "1" || lower === "yes";
  }
  if (typeof value === "number") return value !== 0;
  return defaultValue;
}
