// Client pur pour l'API Google Places (New) -- AUCUNE dependance Firebase
// ici (pas de firebase-functions, pas de Secret Manager, pas d'auth) :
// uniquement id / nom / adresse, le strict necessaire pour presenter des
// resultats de recherche au commercant lors de l'association manuelle
// commercant <-> google_place_id (voir firebase/firestore.rules,
// isSafeMerchantEnseigneUpdate()). Aucune autre donnee Google (note, avis,
// horaires, telephone, site, photos, coordonnees GPS) n'est recuperee ici.
//
// La cle API elle-meme (Secret Manager) est obtenue et transmise par
// l'appelant -- voir google_places_search_callable.js, qui est la seule
// couche a toucher a Firebase / au secret GOOGLE_PLACES_API_KEY. Ce fichier
// reste testable isolement, sans emulateur ni secret reel.

const kMaxResults = 5;
const kPlacesSearchTextUrl =
  "https://places.googleapis.com/v1/places:searchText";

function normalizePlace(place) {
  const displayName =
    place && place.displayName && typeof place.displayName.text === "string"
      ? place.displayName.text.trim()
      : "";
  return {
    placeId: place && typeof place.id === "string" ? place.id.trim() : "",
    name: displayName,
    formattedAddress:
      place && typeof place.formattedAddress === "string"
        ? place.formattedAddress.trim()
        : "",
  };
}

/**
 * Interroge Places API (New) - places:searchText - et normalise les
 * resultats. N'expose et ne journalise jamais `apiKey`.
 *
 * @param {string} query
 * @param {string} apiKey
 * @param {typeof fetch} [fetchImpl] - injectable pour les tests.
 */
async function searchGooglePlacesText(query, apiKey, fetchImpl = fetch) {
  const response = await fetchImpl(kPlacesSearchTextUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
        "places.id,places.displayName,places.formattedAddress",
    },
    body: JSON.stringify({textQuery: query}),
  });

  if (!response.ok) {
    const bodyText = await response.text().catch(() => "");
    // bodyText vient de la reponse Google -- jamais notre cle API -- mais
    // reste tronque par prudence avant de finir dans un message d'erreur.
    throw new Error(
      `Google Places request failed (${response.status}): ${bodyText.slice(0, 300)}`,
    );
  }

  const data = await response.json();
  const places = Array.isArray(data.places) ? data.places : [];
  return places
    .map(normalizePlace)
    .filter((place) => place.placeId)
    .slice(0, kMaxResults);
}

module.exports = {
  kMaxResults,
  normalizePlace,
  searchGooglePlacesText,
};
