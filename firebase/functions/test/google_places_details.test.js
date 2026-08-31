#!/usr/bin/env node

// Pure unit tests for google_places_details.js (Place Details client, no
// Firebase dependency) -- no emulator, no network, no real API key.
//
//   node --test test/google_places_details.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  getGooglePlaceDetails,
  normalizePlaceDetails,
} = require("../google_places_details");

test("normalizePlaceDetails garde uniquement rating/reviewsCount", () => {
  const result = normalizePlaceDetails({
    rating: 4.6,
    userRatingCount: 128,
    displayName: {text: "La Civette Jean Bart"},
    formattedAddress: "11 Place Jean Bart, Dunkerque",
  });
  assert.deepEqual(result, {rating: 4.6, reviewsCount: 128});
});

test("normalizePlaceDetails renvoie null pour des champs absents", () => {
  const result = normalizePlaceDetails({});
  assert.deepEqual(result, {rating: null, reviewsCount: null});
});

test("getGooglePlaceDetails encode le placeId dans l'URL et lit le field mask", async () => {
  let capturedUrl;
  let capturedHeaders;
  const fakeFetch = async (url, options) => {
    capturedUrl = url;
    capturedHeaders = options.headers;
    return {
      ok: true,
      json: async () => ({rating: 4.6, userRatingCount: 128}),
    };
  };
  const result = await getGooglePlaceDetails(
    "ChIJ some/weird id",
    "fake-key",
    fakeFetch,
  );
  assert.equal(
    capturedUrl,
    "https://places.googleapis.com/v1/places/ChIJ%20some%2Fweird%20id",
  );
  assert.equal(capturedHeaders["X-Goog-Api-Key"], "fake-key");
  assert.equal(capturedHeaders["X-Goog-FieldMask"], "rating,userRatingCount");
  assert.deepEqual(result, {rating: 4.6, reviewsCount: 128});
});

test("getGooglePlaceDetails remonte une erreur explicite sur reponse HTTP en echec", async () => {
  const fakeFetch = async () => ({
    ok: false,
    status: 404,
    text: async () => "NOT_FOUND",
  });
  await assert.rejects(
    () => getGooglePlaceDetails("ChIJ123", "fake-key", fakeFetch),
    /Google Place Details request failed \(404\)/,
  );
});

test("getGooglePlaceDetails n'expose jamais la cle API dans une erreur", async () => {
  const secretApiKey = "super-secret-key-should-never-leak";
  const fakeFetch = async () => ({
    ok: false,
    status: 403,
    text: async () => "PERMISSION_DENIED for this request",
  });
  await assert.rejects(
    () => getGooglePlaceDetails("ChIJ123", secretApiKey, fakeFetch),
    (error) => !error.message.includes(secretApiKey),
  );
});
