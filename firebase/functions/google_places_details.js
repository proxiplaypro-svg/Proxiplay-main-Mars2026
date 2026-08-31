// Client pur pour la fiche Google Places (New) - places/{placeId} -- AUCUNE
// dependance Firebase ici, meme logique de separation que
// google_places_search.js. Ne recupere que rating/userRatingCount : rien
// d'autre (pas d'horaires, telephone, site, photos, prix, categories,
// coordonnees GPS).

const kPlaceDetailsUrlBase = "https://places.googleapis.com/v1/places/";

function normalizePlaceDetails(data) {
  return {
    rating: typeof data.rating === "number" ? data.rating : null,
    reviewsCount:
      typeof data.userRatingCount === "number" ? data.userRatingCount : null,
  };
}

/**
 * @param {string} placeId
 * @param {string} apiKey
 * @param {typeof fetch} [fetchImpl] - injectable pour les tests.
 */
async function getGooglePlaceDetails(placeId, apiKey, fetchImpl = fetch) {
  const response = await fetchImpl(
    `${kPlaceDetailsUrlBase}${encodeURIComponent(placeId)}`,
    {
      method: "GET",
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "rating,userRatingCount",
      },
    },
  );

  if (!response.ok) {
    const bodyText = await response.text().catch(() => "");
    throw new Error(
      `Google Place Details request failed (${response.status}): ${bodyText.slice(0, 300)}`,
    );
  }

  const data = await response.json();
  return normalizePlaceDetails(data);
}

module.exports = {getGooglePlaceDetails, normalizePlaceDetails};
