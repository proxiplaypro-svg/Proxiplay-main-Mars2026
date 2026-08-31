// Cloud Function (1re generation, comme le reste de ce projet -- voir
// index.js : aucune fonction n'utilise firebase-functions/v2) qui expose
// google_places_search.js comme callable authentifiee.
//
// Seule cette couche connait Firebase : elle lit le secret Secret Manager
// GOOGLE_PLACES_API_KEY via defineSecret()/runWith({secrets: [...]}) puis
// transmet sa valeur, en memoire, a google_places_search.js. Le secret
// n'est jamais journalise, jamais renvoye au client, et n'existe nulle
// part ailleurs (pas de functions.config(), pas de .env commite, pas de
// Firestore, pas de code Flutter).
//
//   firebase functions:secrets:set GOOGLE_PLACES_API_KEY
//
// La cle doit etre restreinte cote Google Cloud Console a l'API
// "Places API (New)".

const {searchGooglePlacesText} = require("./google_places_search");
const {googlePlacesApiKey} = require("./google_places_secret");

/**
 * @param {object} deps
 * @param {object} deps.functions - le module firebase-functions (1re gen).
 * @param {string} deps.kFunctionsRegion - region deja utilisee par les
 *   autres callables du projet.
 * @param {(value: unknown) => string} deps.getTrimmedString - helper deja
 *   utilise par les autres callables du projet (index.js).
 * @param {typeof fetch} [deps.fetchImpl] - injectable pour les tests.
 * @param {{value: () => string}} [deps.secret] - injectable pour les tests
 *   (par defaut le SecretParam GOOGLE_PLACES_API_KEY reel).
 */
function createSearchGooglePlacesCallable({
  functions: functionsModule,
  kFunctionsRegion,
  getTrimmedString,
  fetchImpl,
  secret = googlePlacesApiKey,
}) {
  return functionsModule
    .region(kFunctionsRegion)
    .runWith({timeoutSeconds: 15, memory: "256MB", secrets: [secret]})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functionsModule.https.HttpsError(
          "unauthenticated",
          "Authentification requise.",
        );
      }

      const query = getTrimmedString(data && data.query);
      if (!query) {
        throw new functionsModule.https.HttpsError(
          "invalid-argument",
          "Un texte de recherche est requis.",
        );
      }

      const apiKey = secret.value();
      if (!apiKey) {
        // On ne journalise jamais la valeur, seulement le fait qu'elle
        // manque -- ce message ne contient et ne peut pas contenir la cle.
        console.error(
          "[SEARCH_GOOGLE_PLACES_CONFIG_MISSING]",
          "GOOGLE_PLACES_API_KEY secret is not set",
        );
        throw new functionsModule.https.HttpsError(
          "failed-precondition",
          "La recherche Google n'est pas encore configuree.",
        );
      }

      try {
        const results = await searchGooglePlacesText(
          query,
          apiKey,
          fetchImpl,
        );
        return {results};
      } catch (error) {
        // error.message peut contenir un extrait de la reponse Google mais
        // jamais notre cle (voir google_places_search.js) ; on ne le
        // renvoie de toute facon jamais au client, seulement aux logs
        // serveur, et le client ne recoit qu'un message generique fixe.
        console.error("[SEARCH_GOOGLE_PLACES_FAILED]", {
          query,
          callerUid: context.auth.uid,
          error: error.message,
        });
        throw new functionsModule.https.HttpsError(
          "unavailable",
          "La recherche Google est momentanement indisponible.",
        );
      }
    });
}

module.exports = {createSearchGooglePlacesCallable, googlePlacesApiKey};
