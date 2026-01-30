const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();

exports.participateInGameTransaction = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez être connecté pour participer.",
      );
    }

    let gameRefPath = data.gameRef;
    console.log("gameRefPath reçu:", gameRefPath);

    if (!gameRefPath || typeof gameRefPath !== "string" || gameRefPath === "") {
      console.error("gameRefPath est invalide:", gameRefPath);
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Référence du jeu invalide.",
      );
    }

    const gameRef = db.collection("games").doc(gameRefPath);
    console.log("gameRef Firestore path:", gameRef.path);

    let responseData = {};

    try {
      await db.runTransaction(async (transaction) => {
        const now = admin.firestore.Timestamp.now();

        const participantsRef = gameRef.collection("participants");
        const userRef = db.collection("users").doc(context.auth.uid);
        const userParticipantRef = participantsRef.doc(context.auth.uid);

        const participantDetailRef = gameRef
          .collection("participants_details")
          .doc(context.auth.uid);

        console.log("UserRef Firestore path:", userRef.path);

        const [gameDoc, userDoc, userParticipantDoc, participantDetailDoc] =
          await Promise.all([
            transaction.get(gameRef),
            transaction.get(userRef),
            transaction.get(userParticipantRef),
            transaction.get(participantDetailRef),
          ]);

        // 1. Référence à la sous-collection
        const instantWinnersRef = gameRef.collection("instant_winners");

        // 2. Construire la query pour le prochain lot instantané non réclamé
        const instantWinnersQuery = instantWinnersRef
          .where("hasWinner", "==", false) // ou 'claimed' == false selon votre schéma
          .where("date", "<=", now) // dateGain déjà passée
          .orderBy("date", "asc")
          .limit(1);

        // 3. Exécuter la query dans la transaction
        const instantWinnerSnap = await transaction.get(instantWinnersQuery);

        if (!gameDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "Le jeu n'existe pas.",
          );
        }
        if (!userDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "Utilisateur introuvable.",
          );
        }

        const gameData = gameDoc.data();
        const userData = userDoc.data();
        const ownerRef = db.doc(gameData.create_by.path);
        const enseigneRef = db.doc(gameData.enseigne_id.path);
        // RÉCUPÉRER LES DONNÉES DE L'ENSEIGNE DANS LA TRANSACTION
        const enseigneDoc = await transaction.get(enseigneRef);
        if (!enseigneDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "L'enseigne associée au jeu n'existe pas.",
          );
        }
        const enseigneData = enseigneDoc.data();
        const enseigneName = enseigneData.name; // En supposant que 'name' est le champ du nom de l'enseigne

        const currentParticipation = gameData.participations || 0;
        const newPosition = currentParticipation + 1;
        const remainingPart = userData.remaining_part || 0;
        const hasMainPrize =
          !!gameData.name ||
          !!gameData.description ||
          gameData.prize_value !== null &&
            typeof gameData.prize_value !== "undefined";

        const endOfDay = new Date();
        endOfDay.setHours(21, 59, 59, 999);
        const endOfDayTimestamp = admin.firestore.Timestamp.fromDate(endOfDay);

        if (remainingPart <= 0) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Vous n'avez plus de parties disponibles.",
          );
        }

        //if (userParticipantDoc.exists) {
        //    throw new functions.https.HttpsError('already-exists', 'Vous êtes déjà inscrit à ce jeu.');
        //}

        if (participantDetailDoc.exists) {
          const detailData = participantDetailDoc.data();
          const lastPlay = detailData.last_play?.toDate?.();
          const nowDate = new Date();
          nowDate.setHours(0, 0, 0, 0);
          const hasPlayedToday = lastPlay && lastPlay >= nowDate;
          const bonus = detailData.game_bonus || 0;

          if (hasPlayedToday && bonus <= 0) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "Vous avez déjà participé aujourd'hui. Partagez le jeu pour rejouer !",
            );
          }

          if (hasPlayedToday && bonus > 0) {
            transaction.update(participantDetailRef, {
              game_bonus: admin.firestore.FieldValue.increment(-1),
            });
          } else {
            transaction.set(
              participantDetailRef,
              {
                last_play: endOfDay,
                game_bonus: bonus,
                user_id: userRef,
              },
              { merge: true },
            );
          }
        } else {
          transaction.set(participantDetailRef, {
            last_play: endOfDay,
            game_bonus: 0,
            user_id: userRef,
          });
        }

        transaction.set(userParticipantRef, {
          user_id: userRef,
          participation_date: now,
        });

        transaction.update(gameRef, {
          participations: admin.firestore.FieldValue.increment(1),
        });

        transaction.update(userRef, {
          remaining_part: admin.firestore.FieldValue.increment(-1),
        });

        let lotGagne = false;
        let lotDetails = null;
        // let prizeRef = db.collection('prizes').doc();
        let prizeRef = null;

        let messageBonus = "";

        if (!instantWinnerSnap.empty) {
          const instantWinnerDoc = instantWinnerSnap.docs[0];
          const instantData = instantWinnerDoc.data();

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

        if (newPosition % 10 === 0) {
          transaction.update(userRef, {
            remaining_part: admin.firestore.FieldValue.increment(3),
          });
          messageBonus = "🎉 Vous avez gagné 3 parties supplémentaires !";
        }

        responseData = {
          message: lotGagne
            ? lotDetails
            : hasMainPrize
              ? "Vous êtes sélectionné pour le grand tirage au sort."
              : "Merci pour votre participation. Aucun tirage final pour ce jeu.",
          messageBonus: messageBonus,
          isWin: lotGagne,
          prize_id: prizeRef ? prizeRef.path : null, // ✅ Corrigé ici
        };
      });

      console.log("✅ Retour des données FINAL :", responseData);
      return responseData;
    } catch (error) {
      console.error("Erreur lors de la participation au jeu :", error);
      throw new functions.https.HttpsError(
        "internal",
        error.message || "Une erreur est survenue.",
      );
    }
  },
);
