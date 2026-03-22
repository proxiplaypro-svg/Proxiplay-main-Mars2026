const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();

function getParisDayKey(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((p) => p.type === "year")?.value || "";
  const month = parts.find((p) => p.type === "month")?.value || "";
  const day = parts.find((p) => p.type === "day")?.value || "";
  return `${year}${month}${day}`;
}

function sanitizeDisplayText(value) {
  if (typeof value !== "string") return "";
  let output = value;

  const replacements = {
    "\u00C3\u00A9": "\u00E9",
    "\u00C3\u00A8": "\u00E8",
    "\u00C3\u00A0": "\u00E0",
    "\u00C3\u00A2": "\u00E2",
    "\u00C3\u00AA": "\u00EA",
    "\u00C3\u00AE": "\u00EE",
    "\u00C3\u00B4": "\u00F4",
    "\u00C3\u00BB": "\u00FB",
    "\u00C3\u00A7": "\u00E7",
    "\u00E2\u20AC\u2122": "'",
    "\u00E2\u20AC\u02DC": "'",
    "\u00E2\u20AC\u0153": "\"",
    "\u00E2\u20AC\u009D": "\"",
    "\u00E2\u20AC\u00A6": "...",
    "\u00E2\u20AC\u0093": "-",
    "\u00E2\u20AC\u0094": "-",
    "\u00E2\u20AC\u00AC": "\u20AC",
    "\u00C2\u00A0": " ",
  };

  Object.entries(replacements).forEach(([source, target]) => {
    output = output.split(source).join(target);
  });

  output = output.replace(/\u00F0[\u0080-\u00BF]{2,4}/g, "");
  output = output.replace(/\u00C3[\u0080-\u00BF]/g, "");
  output = output.replace(/\u00E2[\u0080-\u00BF]{1,2}/g, "");
  output = output.replace(/ð[\wÀ-ÿ]*/g, "");
  output = output.replace(/Ã[\wÀ-ÿ]*/g, "");
  output = output.replace(/[^\t\n\r\x20-\x7E\u00A0-\u00FF]/g, "");
  output = output.replace(/\s+/g, " ").trim();
  output = output.replace(/^[^A-Za-zÀ-ÖØ-öø-ÿ0-9]+/, "");
  return output;
}

function hasUnlimitedAccess(userData, now) {
  const accessUntil = userData && userData.allGamesAccessUntil;
  if (!accessUntil || typeof accessUntil.toMillis !== "function") {
    return false;
  }
  return accessUntil.toMillis() > now.toMillis();
}

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

exports.participateInGameTransaction = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez ÃƒÂªtre connectÃƒÂ© pour participer."
      );
    }

    let gameRefPath = data.gameRef;
    console.log("gameRefPath reÃƒÂ§u:", gameRefPath);

    if (!gameRefPath || typeof gameRefPath !== "string" || gameRefPath === "") {
      console.error("gameRefPath est invalide:", gameRefPath);
      throw new functions.https.HttpsError(
        "invalid-argument",
        "RÃƒÂ©fÃƒÂ©rence du jeu invalide."
      );
    }

    const gameRef = db.collection("games").doc(gameRefPath);
    console.log("gameRef Firestore path:", gameRef.path);

    let responseData = {};

    try {
      await db.runTransaction(async (transaction) => {
        const now = admin.firestore.Timestamp.now();
        const uid = context.auth.uid;
        const dayKey = getParisDayKey(new Date());
        const participantDocId = `${dayKey}_${uid}`;

        const participantsRef = gameRef.collection("participants");
        const userRef = db.collection("users").doc(uid);
        const participantTodayRef = participantsRef.doc(participantDocId);
        const uniquePlayerRef = gameRef
          .collection("unique_players")
          .doc(uid);

        const participantDetailRef = gameRef
          .collection("participants_details")
          .doc(uid);

        console.log("UserRef Firestore path:", userRef.path);

        const [
          gameDoc,
          userDoc,
          participantTodayDoc,
          participantDetailDoc,
          uniquePlayerDoc,
        ] =
          await Promise.all([
            transaction.get(gameRef),
            transaction.get(userRef),
            transaction.get(participantTodayRef),
            transaction.get(participantDetailRef),
            transaction.get(uniquePlayerRef),
          ]);

        // 1. RÃƒÂ©fÃƒÂ©rence ÃƒÂ  la sous-collection
        const instantWinnersRef = gameRef.collection("instant_winners");

        // 2. Query prochain lot instantanÃƒÂ© non rÃƒÂ©clamÃƒÂ©
        const instantWinnersQuery = instantWinnersRef
          .where("hasWinner", "==", false)
          .where("date", "<=", now)
          .orderBy("date", "asc")
          .limit(1);

        // 3. ExÃƒÂ©cuter la query dans la transaction
        const instantWinnerSnap = await transaction.get(instantWinnersQuery);

        if (!gameDoc.exists) {
          throw new functions.https.HttpsError("not-found", "Le jeu n'existe pas.");
        }
        if (!userDoc.exists) {
          throw new functions.https.HttpsError("not-found", "Utilisateur introuvable.");
        }

        const gameData = gameDoc.data();
        const userData = userDoc.data();
        const ownerRef = db.doc(gameData.create_by.path);
        const enseigneRef = db.doc(gameData.enseigne_id.path);

        // RÃƒÂ©cupÃƒÂ©rer l'enseigne
        const enseigneDoc = await transaction.get(enseigneRef);
        if (!enseigneDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "L'enseigne associÃƒÂ©e au jeu n'existe pas."
          );
        }
        const enseigneData = enseigneDoc.data();
        const enseigneName = enseigneData.name;

        const currentParticipation = gameData.participations || 0;
        const newPosition = currentParticipation + 1;
        const remainingPart = userData.remaining_part || 0;
        const alreadyParticipatedToday = participantTodayDoc.exists;
        const unlimitedAccessActive = hasUnlimitedAccess(userData, now);
        let uniquePlayerNew = false;

        // DÃƒÂ©tection lot principal (sert uniquement ÃƒÂ  la cohÃƒÂ©rence des champs, pas au message de perte)
        const hasMainPrizeField = Object.prototype.hasOwnProperty.call(
          gameData || {},
          "hasMainPrize"
        );
        const hasMainPrize = hasMainPrizeField
          ? gameData.hasMainPrize === true
          : (
              (typeof gameData.name === "string" && gameData.name.trim().length > 0) ||
              (typeof gameData.description === "string" && gameData.description.trim().length > 0) ||
              (gameData.prize_value !== null && typeof gameData.prize_value !== "undefined")
            );

        // Patch cohÃƒÂ©rence: si pas de lot principal -> pas de winner / tirage au sort
        const gameConsistencyPatch = {};
        if (!hasMainPrizeField) {
          gameConsistencyPatch.hasMainPrize = hasMainPrize;
        }
        if (
          !hasMainPrize &&
          (gameData.hasWinner === true || !!gameData.main_prize_winner)
        ) {
          gameConsistencyPatch.hasWinner = false;
          gameConsistencyPatch.main_prize_winner = null;
        }
        if (Object.keys(gameConsistencyPatch).length > 0) {
          transaction.update(gameRef, gameConsistencyPatch);
        }

        const endOfDay = new Date();
        endOfDay.setHours(21, 59, 59, 999);

        if (remainingPart <= 0 && !unlimitedAccessActive) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Vous n'avez plus de parties disponibles."
          );
        }

        if (!uniquePlayerDoc.exists) {
          uniquePlayerNew = true;
          transaction.set(uniquePlayerRef, {
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          transaction.update(gameRef, {
            unique_players_count: admin.firestore.FieldValue.increment(1),
          });
        }

        if (alreadyParticipatedToday) {
          console.log(
            `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true uniquePlayerNew=${uniquePlayerNew}`
          );
          responseData = {
            message: "Vous avez déjà participé aujourd'hui.",
            messageBonus: "",
            isWin: false,
            prize_id: null,
            alreadyParticipatedToday: true,
          };
          return;
        }

        // Bonus/jour
        if (participantDetailDoc.exists) {
          const detailData = participantDetailDoc.data();
          const lastPlay = detailData.last_play?.toDate?.();
          const nowDate = new Date();
          nowDate.setHours(0, 0, 0, 0);
          const hasPlayedToday = lastPlay && lastPlay >= nowDate;
          const bonus = detailData.game_bonus || 0;

          if (hasPlayedToday && bonus <= 0) {
            console.log(
              `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true(unique-last-play) uniquePlayerNew=${uniquePlayerNew}`
            );
            responseData = {
              message: "Vous avez déjà participé aujourd'hui.",
              messageBonus: "",
              isWin: false,
              prize_id: null,
              alreadyParticipatedToday: true,
            };
            return;
          }

          if (hasPlayedToday && bonus > 0) {
            console.log(
              `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true(bonus) uniquePlayerNew=${uniquePlayerNew}`
            );
            responseData = {
              message: "Vous avez déjà participé aujourd'hui.",
              messageBonus: "",
              isWin: false,
              prize_id: null,
              alreadyParticipatedToday: true,
            };
            return;
          } else {
            transaction.set(
              participantDetailRef,
              {
                last_play: endOfDay,
                game_bonus: bonus,
                user_id: userRef,
              },
              { merge: true }
            );
          }
        } else {
          transaction.set(participantDetailRef, {
            last_play: endOfDay,
            game_bonus: 0,
            user_id: userRef,
          });
        }

        // Enregistrer participation
        transaction.set(participantTodayRef, {
          user_id: userRef,
          participation_date: now,
        });


        transaction.update(gameRef, {
          participations: admin.firestore.FieldValue.increment(1),
        });

        let messageBonus = "";
        let remainingPartDelta = 0;
        if (!unlimitedAccessActive) {
          remainingPartDelta -= 1;
        }

        // Bonus toutes les 10 participations
        if (newPosition % 10 === 0) {
          remainingPartDelta += 3;
          messageBonus = "Vous avez gagné 3 parties supplémentaires !";
        }

        // Mettre à jour l'activité réelle du joueur et les statistiques
        const userUpdateData = {
          last_real_activity_at: now,
          games_played_count: admin.firestore.FieldValue.increment(1),
        };

        if (remainingPartDelta !== 0) {
          userUpdateData.remaining_part = remainingPart + remainingPartDelta;
        }

        // Calculer le nouveau statut du joueur basé sur son activité
        // Remarque : games_played_count est déjà incrémenté ci-dessus,
        // mais la transaction n'a pas encore committée. On doit passer la valeur future.
        const projectedGamesPlayedCount = (userData.games_played_count || 0) + 1;
        const projectedUserData = {
          ...userData,
          last_real_activity_at: now,
          games_played_count: projectedGamesPlayedCount,
        };
        userUpdateData.player_status_cached = calculatePlayerStatus(projectedUserData, now);

        transaction.update(userRef, userUpdateData);

        // Lots (gains immÃƒÂ©diats uniquement)
        let lotGagne = false;
        let lotDetails = null;
        let prizeRef = null;

        if (!instantWinnerSnap.empty) {
          const instantWinnerDoc = instantWinnerSnap.docs[0];

          const claim_code = `${Date.now().toString(36).toUpperCase()}`;

          transaction.update(instantWinnerDoc.ref, {
            hasWinner: true,
            player_id: userRef,
          });

          prizeRef = db.collection("prizes").doc();

          transaction.set(prizeRef, {
            prize_type: "secondaire",
            name: gameData.secondary_prize_description,
            winner_id: userRef,
            game_id: gameRef,
            enseigne_id: enseigneRef,
            enseigne_name: enseigneName,
            owner_id: ownerRef,
            claim_code: claim_code,
            claimed: false,
            win_date: now,
          });

          const userLotRef = userRef.collection("my_lots").doc(prizeRef.id);
          transaction.set(userLotRef, {
            prize_id: prizeRef,
          });

          lotGagne = true;
          lotDetails = gameData.secondary_prize_description;
        }

        // Messages aleatoires a afficher en cas de perte
        const loseMessages = [
          "Retente ta chance demain !",
          "A demain pour une nouvelle partie.",
          "Reviens demain pour une nouvelle tentative !",
        ];

        // Message principal renvoye a l'app :
        // - Si gain immÃƒÂ©diat => lotDetails
        // - Si perte => message alÃƒÂ©atoire (mÃƒÂªme si pas de lot principal)
        const message = lotGagne
          ? lotDetails
          : loseMessages[Math.floor(Math.random() * loseMessages.length)];

        responseData = {
          message,
          messageBonus,
          isWin: lotGagne,
          prize_id: prizeRef ? prizeRef.path : null,
          alreadyParticipatedToday: false,
          // Optionnel: garde l'info cÃƒÂ´tÃƒÂ© app si besoin un jour
          // hasMainPrize,
        };
        console.log(`participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=false uniquePlayerNew=${uniquePlayerNew}`);
      });

      console.log("Retour des données FINAL :", responseData);
      responseData = {
        ...responseData,
        message: sanitizeDisplayText(responseData.message || ""),
        messageBonus: sanitizeDisplayText(responseData.messageBonus || ""),
      };
      return responseData;
    } catch (error) {
      console.error("Erreur lors de la participation au jeu :", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        error.message || "Une erreur est survenue."
      );
    }
  }
);

