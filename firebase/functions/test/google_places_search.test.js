#!/usr/bin/env node

// Pure unit tests for google_places_search.js (the Places API client, no
// Firebase dependency) -- no emulator, no network, no real Google Places
// API key required. Covers: field normalization, HTTP failure propagation,
// and result capping. The live network call itself cannot be tested here
// (no real Google Places API key is available in this sandbox).
//
// Callable-specific behaviour (auth, secret handling, error mapping) lives
// in google_places_search_callable.test.js.
//
//   node --test test/google_places_search.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizePlace,
  searchGooglePlacesText,
} = require("../google_places_search");

test("normalizePlace ne garde que placeId/name/formattedAddress", () => {
  const result = normalizePlace({
    id: "ChIJ123",
    displayName: {text: "La Civette Jean Bart", languageCode: "fr"},
    formattedAddress: "11 Place Jean Bart, 59140 Dunkerque, France",
    rating: 4.6,
    userRatingCount: 128,
  });
  assert.deepEqual(result, {
    placeId: "ChIJ123",
    name: "La Civette Jean Bart",
    formattedAddress: "11 Place Jean Bart, 59140 Dunkerque, France",
  });
});

test("normalizePlace gere un resultat incomplet sans planter", () => {
  const result = normalizePlace({});
  assert.deepEqual(result, {placeId: "", name: "", formattedAddress: ""});
});

test("searchGooglePlacesText normalise et plafonne a 5 resultats", async () => {
  const places = Array.from({length: 8}, (_, i) => ({
    id: `ChIJ${i}`,
    displayName: {text: `Etablissement ${i}`},
    formattedAddress: `${i} Rue du Test`,
  }));
  const fakeFetch = async () => ({
    ok: true,
    json: async () => ({places}),
  });
  const results = await searchGooglePlacesText(
    "La Civette",
    "fake-key",
    fakeFetch,
  );
  assert.equal(results.length, 5);
  assert.equal(results[0].placeId, "ChIJ0");
});

test("searchGooglePlacesText remonte une erreur explicite sur reponse HTTP en echec", async () => {
  const fakeFetch = async () => ({
    ok: false,
    status: 403,
    text: async () => "PERMISSION_DENIED",
  });
  await assert.rejects(
    () => searchGooglePlacesText("La Civette", "fake-key", fakeFetch),
    /Google Places request failed \(403\)/,
  );
});

test("searchGooglePlacesText n'expose jamais la cle API dans une erreur", async () => {
  const secretApiKey = "super-secret-key-should-never-leak";
  const fakeFetch = async () => ({
    ok: false,
    status: 403,
    text: async () => "PERMISSION_DENIED for this request",
  });
  await assert.rejects(
    () => searchGooglePlacesText("La Civette", secretApiKey, fakeFetch),
    (error) => !error.message.includes(secretApiKey),
  );
});
