// Cloud Function (1re generation, Firestore trigger -- meme famille que les
// autres triggers onWrite/onCreate de ce projet dans index.js) qui tient
// google_rating/google_reviews_count a jour sur enseignes/{enseigneId}
// chaque fois que google_place_id est associe ou remplace.
//
// Se declenche sur TOUTE ecriture du document mais ne fait quelque chose
// que si google_place_id a change entre avant et apres -- sinon (y compris
// sur sa PROPRE ecriture de google_rating juste apres), elle ne fait rien,
// ce qui evite toute boucle infinie.
//
// Reutilise le secret GOOGLE_PLACES_API_KEY (google_places_secret.js),
// deja configure pour searchGooglePlaces -- aucune configuration
// supplementaire requise.

const {getGooglePlaceDetails} = require("./google_places_details");
const {googlePlacesApiKey} = require("./google_places_secret");

function getStringField(data, key) {
  const value = data && data[key];
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

/**
 * Coeur testable de la logique, sans aucune dependance Firebase : decide
 * quoi faire a partir du placeId avant/apres, sans savoir comment lire ou
 * ecrire Firestore.
 *
 * @param {object} params
 * @param {string|null} params.beforePlaceId
 * @param {string|null} params.afterPlaceId
 * @param {(placeId: string) => Promise<{rating: number|null, reviewsCount: number|null}>} params.fetchDetails
 * @returns {Promise<
 *   {action: "skip"} |
 *   {action: "clear"} |
 *   {action: "update", details: {rating: number|null, reviewsCount: number|null}} |
 *   {action: "error", error: Error}
 * >}
 */
async function computeEnseigneRatingUpdate({
  beforePlaceId,
  afterPlaceId,
  fetchDetails,
}) {
  if (beforePlaceId === afterPlaceId) {
    return {action: "skip"};
  }

  if (!afterPlaceId) {
    return {action: "clear"};
  }

  try {
    const details = await fetchDetails(afterPlaceId);
    return {action: "update", details};
  } catch (error) {
    return {action: "error", error};
  }
}

/**
 * @param {object} deps
 * @param {object} deps.functions - le module firebase-functions (1re gen).
 * @param {object} deps.admin - le module firebase-admin (pour FieldValue/Timestamp).
 * @param {string} deps.kFunctionsRegion
 * @param {typeof fetch} [deps.fetchImpl] - injectable pour les tests.
 * @param {{value: () => string}} [deps.secret] - injectable pour les tests.
 */
function createRefreshGooglePlaceRatingTrigger({
  functions: functionsModule,
  admin,
  kFunctionsRegion,
  fetchImpl,
  secret = googlePlacesApiKey,
}) {
  return functionsModule
    .region(kFunctionsRegion)
    .runWith({timeoutSeconds: 30, memory: "256MB", secrets: [secret]})
    .firestore.document("enseignes/{enseigneId}")
    .onWrite(async (change, context) => {
      if (!change.after.exists) {
        // Enseigne supprimee -- rien a rafraichir.
        return null;
      }

      const beforeData = change.before.exists ? change.before.data() : {};
      const afterData = change.after.data();
      const beforePlaceId = getStringField(beforeData, "google_place_id");
      const afterPlaceId = getStringField(afterData, "google_place_id");

      const result = await computeEnseigneRatingUpdate({
        beforePlaceId,
        afterPlaceId,
        fetchDetails: (placeId) => {
          const apiKey = secret.value();
          if (!apiKey) {
            throw new Error("GOOGLE_PLACES_API_KEY secret is not set");
          }
          return getGooglePlaceDetails(placeId, apiKey, fetchImpl);
        },
      });

      const enseigneRef = change.after.ref;

      if (result.action === "clear") {
        await enseigneRef.update({
          google_rating: admin.firestore.FieldValue.delete(),
          google_reviews_count: admin.firestore.FieldValue.delete(),
          google_rating_updated_at: admin.firestore.FieldValue.delete(),
        });
        return null;
      }

      if (result.action === "update") {
        const {rating, reviewsCount} = result.details;
        await enseigneRef.update({
          google_rating:
            rating === null
              ? admin.firestore.FieldValue.delete()
              : rating,
          google_reviews_count:
            reviewsCount === null
              ? admin.firestore.FieldValue.delete()
              : reviewsCount,
          google_rating_updated_at: admin.firestore.Timestamp.now(),
        });
        return null;
      }

      if (result.action === "error") {
        // result.error.message peut contenir un extrait de la reponse
        // Google mais jamais la cle (voir google_places_details.js).
        console.error("[REFRESH_GOOGLE_PLACE_RATING_FAILED]", {
          enseigneId: context.params.enseigneId,
          placeId: afterPlaceId,
          error: result.error.message,
        });
        return null;
      }

      // action === "skip" : google_place_id inchange, rien a faire.
      return null;
    });
}

module.exports = {
  createRefreshGooglePlaceRatingTrigger,
  computeEnseigneRatingUpdate,
};
