#!/usr/bin/env node

// Unit tests for google_place_rating_refresh.js: both the pure decision
// core (computeEnseigneRatingUpdate, no Firebase dependency) and the
// Firestore trigger glue (createRefreshGooglePlaceRatingTrigger), with
// firebase-functions/firebase-admin/fetch all faked/injected. No emulator,
// no network, no real GOOGLE_PLACES_API_KEY secret required or used.
//
//   node --test test/google_place_rating_refresh.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  computeEnseigneRatingUpdate,
  createRefreshGooglePlaceRatingTrigger,
} = require("../google_place_rating_refresh");

// --- computeEnseigneRatingUpdate (pure) ---------------------------------

test("skip quand google_place_id est inchange (absent avant et apres)", async () => {
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: null,
    afterPlaceId: null,
    fetchDetails: async () => {
      throw new Error("fetchDetails ne doit jamais etre appele");
    },
  });
  assert.deepEqual(result, {action: "skip"});
});

test("skip quand google_place_id est inchange (meme valeur avant/apres)", async () => {
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: "ChIJ123",
    afterPlaceId: "ChIJ123",
    fetchDetails: async () => {
      throw new Error("fetchDetails ne doit jamais etre appele");
    },
  });
  assert.deepEqual(result, {action: "skip"});
});

test("clear quand google_place_id est retire", async () => {
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: "ChIJ123",
    afterPlaceId: null,
    fetchDetails: async () => {
      throw new Error("fetchDetails ne doit jamais etre appele");
    },
  });
  assert.deepEqual(result, {action: "clear"});
});

test("update quand google_place_id est ajoute et la recuperation reussit", async () => {
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: null,
    afterPlaceId: "ChIJ123",
    fetchDetails: async (placeId) => {
      assert.equal(placeId, "ChIJ123");
      return {rating: 4.6, reviewsCount: 128};
    },
  });
  assert.deepEqual(result, {
    action: "update",
    details: {rating: 4.6, reviewsCount: 128},
  });
});

test("update declenche aussi sur un remplacement (avant et apres tous deux non-null, differents)", async () => {
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: "ChIJold",
    afterPlaceId: "ChIJnew",
    fetchDetails: async (placeId) => {
      assert.equal(placeId, "ChIJnew");
      return {rating: 4.0, reviewsCount: 10};
    },
  });
  assert.equal(result.action, "update");
});

test("error quand la recuperation echoue", async () => {
  const boom = new Error("Google Place Details request failed (403): ...");
  const result = await computeEnseigneRatingUpdate({
    beforePlaceId: null,
    afterPlaceId: "ChIJ123",
    fetchDetails: async () => {
      throw boom;
    },
  });
  assert.equal(result.action, "error");
  assert.equal(result.error, boom);
});

// --- createRefreshGooglePlaceRatingTrigger (Firestore trigger glue) ----

function fakeFunctionsModule() {
  const module = {
    region: () => module,
    runWith: () => module,
    firestore: {
      document: () => ({
        onWrite: (handler) => handler,
      }),
    },
  };
  return module;
}

function fakeAdmin() {
  return {
    firestore: {
      FieldValue: {delete: () => "FIELD_VALUE_DELETE"},
      Timestamp: {now: () => "TIMESTAMP_NOW"},
    },
  };
}

function fakeSecret(value) {
  return {value: () => value};
}

function fakeChange({beforeData, afterData}) {
  const updateCalls = [];
  const afterExists = afterData !== null;
  return {
    updateCalls,
    change: {
      before: {
        exists: beforeData !== null,
        data: () => beforeData ?? {},
      },
      after: {
        exists: afterExists,
        data: () => afterData ?? {},
        ref: {
          update: async (patch) => {
            updateCalls.push(patch);
          },
        },
      },
    },
  };
}

test("trigger : ne fait rien si google_place_id est inchange", async () => {
  const handler = createRefreshGooglePlaceRatingTrigger({
    functions: fakeFunctionsModule(),
    admin: fakeAdmin(),
    kFunctionsRegion: "us-central1",
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => {
      throw new Error("ne doit jamais etre appele");
    },
  });
  const {change, updateCalls} = fakeChange({
    beforeData: {name: "Test", google_place_id: "ChIJ123"},
    afterData: {name: "Test renomme", google_place_id: "ChIJ123"},
  });
  await handler(change, {params: {enseigneId: "e1"}});
  assert.deepEqual(updateCalls, []);
});

test("trigger : nettoie la note quand google_place_id est retire", async () => {
  const handler = createRefreshGooglePlaceRatingTrigger({
    functions: fakeFunctionsModule(),
    admin: fakeAdmin(),
    kFunctionsRegion: "us-central1",
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => {
      throw new Error("ne doit jamais etre appele");
    },
  });
  const {change, updateCalls} = fakeChange({
    beforeData: {google_place_id: "ChIJ123"},
    afterData: {},
  });
  await handler(change, {params: {enseigneId: "e1"}});
  assert.deepEqual(updateCalls, [
    {
      google_rating: "FIELD_VALUE_DELETE",
      google_reviews_count: "FIELD_VALUE_DELETE",
      google_rating_updated_at: "FIELD_VALUE_DELETE",
    },
  ]);
});

test("trigger : ecrit la note quand google_place_id est associe et le secret est present", async () => {
  const handler = createRefreshGooglePlaceRatingTrigger({
    functions: fakeFunctionsModule(),
    admin: fakeAdmin(),
    kFunctionsRegion: "us-central1",
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({rating: 4.6, userRatingCount: 128}),
    }),
  });
  const {change, updateCalls} = fakeChange({
    beforeData: {},
    afterData: {google_place_id: "ChIJ123"},
  });
  await handler(change, {params: {enseigneId: "e1"}});
  assert.deepEqual(updateCalls, [
    {
      google_rating: 4.6,
      google_reviews_count: 128,
      google_rating_updated_at: "TIMESTAMP_NOW",
    },
  ]);
});

test("trigger : n'ecrit rien et journalise (sans planter) si le secret est absent", async () => {
  const originalConsoleError = console.error;
  const loggedCalls = [];
  console.error = (...args) => loggedCalls.push(args);
  try {
    const handler = createRefreshGooglePlaceRatingTrigger({
      functions: fakeFunctionsModule(),
      admin: fakeAdmin(),
      kFunctionsRegion: "us-central1",
      secret: fakeSecret(""),
      fetchImpl: async () => {
        throw new Error("ne doit jamais etre appele sans cle");
      },
    });
    const {change, updateCalls} = fakeChange({
      beforeData: {},
      afterData: {google_place_id: "ChIJ123"},
    });
    await handler(change, {params: {enseigneId: "e1"}});
    assert.deepEqual(updateCalls, []);
    assert.equal(loggedCalls.length, 1);
    assert.equal(loggedCalls[0][0], "[REFRESH_GOOGLE_PLACE_RATING_FAILED]");
  } finally {
    console.error = originalConsoleError;
  }
});

test("trigger : ne fait rien si le document a ete supprime", async () => {
  const handler = createRefreshGooglePlaceRatingTrigger({
    functions: fakeFunctionsModule(),
    admin: fakeAdmin(),
    kFunctionsRegion: "us-central1",
    secret: fakeSecret("fake-key"),
    fetchImpl: async () => {
      throw new Error("ne doit jamais etre appele");
    },
  });
  const {change, updateCalls} = fakeChange({
    beforeData: {google_place_id: "ChIJ123"},
    afterData: null,
  });
  await handler(change, {params: {enseigneId: "e1"}});
  assert.deepEqual(updateCalls, []);
});

test("trigger : la cle API n'apparait jamais dans les logs d'erreur", async () => {
  const secretValue = "super-secret-key-should-never-leak";
  const originalConsoleError = console.error;
  const loggedCalls = [];
  console.error = (...args) => loggedCalls.push(args);
  try {
    const handler = createRefreshGooglePlaceRatingTrigger({
      functions: fakeFunctionsModule(),
      admin: fakeAdmin(),
      kFunctionsRegion: "us-central1",
      secret: fakeSecret(secretValue),
      fetchImpl: async () => ({
        ok: false,
        status: 403,
        text: async () => "PERMISSION_DENIED",
      }),
    });
    const {change} = fakeChange({
      beforeData: {},
      afterData: {google_place_id: "ChIJ123"},
    });
    await handler(change, {params: {enseigneId: "e1"}});
    assert.ok(!JSON.stringify(loggedCalls).includes(secretValue));
  } finally {
    console.error = originalConsoleError;
  }
});
