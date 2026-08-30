#!/usr/bin/env node

// Unit tests for the searchGooglePlaces Cloud Function glue
// (google_places_search_callable.js): auth enforcement, Secret Manager
// value handling (present/absent), error mapping, and result shape --
// with the secret, HTTP fetch, and firebase-functions module all faked/
// injected. No emulator, no network, no real GOOGLE_PLACES_API_KEY secret
// required or used.
//
//   node --test test/google_places_search_callable.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createSearchGooglePlacesCallable,
} = require("../google_places_search_callable");

function fakeFunctionsModule() {
  const module = {
    region: () => module,
    runWith: () => module,
    https: {
      onCall: (handler) => handler,
      HttpsError: class HttpsError extends Error {
        constructor(code, message) {
          super(message);
          this.code = code;
        }
      },
    },
  };
  return module;
}

function fakeSecret(value) {
  return {value: () => value};
}

const getTrimmedString = (v) => (typeof v === "string" ? v.trim() : "");

test("callable : erreur unauthenticated sans contexte auth", async () => {
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret("fake-key"),
  });

  await assert.rejects(
    () => callable({query: "La Civette"}, {auth: null}),
    (error) => error.code === "unauthenticated",
  );
});

test("callable : erreur invalid-argument si aucune requete fournie", async () => {
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => ({ok: true, json: async () => ({places: []})}),
  });

  await assert.rejects(
    () => callable({query: "   "}, {auth: {uid: "merchant_uid"}}),
    (error) => error.code === "invalid-argument",
  );
});

test("callable : erreur failed-precondition si le secret est absent/vide", async () => {
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret(""),
    fetchImpl: async () => {
      throw new Error("fetch should never be called without an API key");
    },
  });

  await assert.rejects(
    () => callable({query: "La Civette"}, {auth: {uid: "merchant_uid"}}),
    (error) => error.code === "failed-precondition",
  );
});

test("callable : renvoie des resultats normalises quand le secret est present", async () => {
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        places: [
          {
            id: "ChIJ123",
            displayName: {text: "La Civette Jean Bart"},
            formattedAddress: "11 Place Jean Bart, Dunkerque",
          },
        ],
      }),
    }),
  });

  const response = await callable(
    {query: "La Civette Jean Bart"},
    {auth: {uid: "merchant_uid"}},
  );
  assert.deepEqual(response, {
    results: [
      {
        placeId: "ChIJ123",
        name: "La Civette Jean Bart",
        formattedAddress: "11 Place Jean Bart, Dunkerque",
      },
    ],
  });
});

test("callable : plafonne a 5 resultats de bout en bout", async () => {
  const places = Array.from({length: 9}, (_, i) => ({
    id: `ChIJ${i}`,
    displayName: {text: `Etablissement ${i}`},
    formattedAddress: `${i} Rue du Test`,
  }));
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => ({ok: true, json: async () => ({places})}),
  });

  const response = await callable(
    {query: "Etablissement"},
    {auth: {uid: "merchant_uid"}},
  );
  assert.equal(response.results.length, 5);
});

test("callable : erreur Google mappee en unavailable, sans jamais exposer la cle", async () => {
  const secretValue = "super-secret-key-should-never-leak";
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret(secretValue),
    fetchImpl: async () => ({
      ok: false,
      status: 403,
      text: async () => "PERMISSION_DENIED",
    }),
  });

  await assert.rejects(
    () => callable({query: "La Civette"}, {auth: {uid: "merchant_uid"}}),
    (error) =>
      error.code === "unavailable" &&
      !error.message.includes(secretValue) &&
      !JSON.stringify(error).includes(secretValue),
  );
});

test("callable : la cle API n'apparait jamais dans la reponse de succes", async () => {
  const secretValue = "super-secret-key-should-never-leak";
  const callable = createSearchGooglePlacesCallable({
    functions: fakeFunctionsModule(),
    kFunctionsRegion: "us-central1",
    getTrimmedString,
    secret: fakeSecret(secretValue),
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        places: [
          {
            id: "ChIJ123",
            displayName: {text: "La Civette Jean Bart"},
            formattedAddress: "11 Place Jean Bart, Dunkerque",
          },
        ],
      }),
    }),
  });

  const response = await callable(
    {query: "La Civette"},
    {auth: {uid: "merchant_uid"}},
  );
  assert.ok(!JSON.stringify(response).includes(secretValue));
});
