#!/usr/bin/env node

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-monthly-challenge-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const {
  buildChallengeStateResponse,
  computeMonthlyChallengeStats,
  drawWinnerForMonthlyChallenge,
  queueMonthlyChallengeNotifications,
  trackMonthlyChallengeParticipation,
  trackMonthlyChallengesParticipation,
} = require("../monthly_challenge.js");

if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(
    collections.map(async (collection) => {
      await firestore.recursiveDelete(collection);
    }),
  );
}

function timestampFromIso(isoString) {
  return admin.firestore.Timestamp.fromDate(new Date(isoString));
}

async function seedUser(uid, data = {}) {
  await firestore.collection("users").doc(uid).set({
    uid,
    user_role: "joueur",
    first_name: uid,
    ...data,
  });
}

async function seedConfig({
  month = "2026-08",
  targetDays = 15,
  drawDate = "2026-10-01T09:00:00.000Z",
  enabled = true,
} = {}) {
  await firestore.doc("app_config/monthly_challenge").set({
    enabled,
    month,
    title: "Defi Proxiplay",
    description: "Joue plusieurs jours differents pour participer au tirage.",
    target_days: targetDays,
    prize_title: "Un resto pour 2",
    prize_description: "Bon cadeau restaurant",
    prize_value: 120,
    draw_date: timestampFromIso(drawDate),
  });
}

async function seedChallenge({
  type = "attendance",
  month = "2026-08",
  targetDays = 15,
  drawDate = "2026-10-01T09:00:00.000Z",
  enabled = true,
  restaurantName = "La Cocotte",
} = {}) {
  const challengeId = type === "restaurant" ? `restaurant_${month}` : month;
  await firestore.collection("monthly_challenges").doc(challengeId).set({
    challenge_id: challengeId,
    type,
    enabled,
    month,
    title: type === "restaurant" ? "Resto du mois" : "Defi Proxiplay",
    description: "Joue plusieurs jours differents pour participer au tirage.",
    target_days: targetDays,
    prize_title: type === "restaurant" ? `Un repas pour 2 chez ${restaurantName}` : "Une console",
    prize_description: "Lot mensuel",
    prize_value: 120,
    restaurant_ref: type === "restaurant" ? firestore.doc("enseignes/resto-1") : null,
    restaurant_name: type === "restaurant" ? restaurantName : "",
    draw_date: timestampFromIso(drawDate),
  });
}

async function track(uid, isoString) {
  const userRef = firestore.collection("users").doc(uid);
  const now = timestampFromIso(isoString);
  return firestore.runTransaction(async (transaction) =>
    trackMonthlyChallengeParticipation({
      uid,
      userRef,
      now,
      transaction,
    }),
  );
}

async function trackAll(uid, isoString) {
  const userRef = firestore.collection("users").doc(uid);
  const now = timestampFromIso(isoString);
  return firestore.runTransaction(async (transaction) =>
    trackMonthlyChallengesParticipation({uid, userRef, now, transaction}),
  );
}

async function getState(uid, month = "2026-08") {
  const snap = await firestore
    .collection("users")
    .doc(uid)
    .collection("monthly_challenges")
    .doc(month)
    .get();
  return snap.exists ? snap.data() || {} : null;
}

async function getNotificationDocs() {
  const snap = await firestore.collection("ff_push_notifications").get();
  return snap.docs;
}

function buildIsoDay(monthKey, day, hour = 10) {
  return `${monthKey}-${String(day).padStart(2, "0")}T${String(hour).padStart(2, "0")}:00:00.000Z`;
}

function buildConfigForDraw({
  month = "2026-07",
  targetDays = 15,
  drawDate = "2026-08-01T09:00:00.000Z",
  enabled = true,
} = {}) {
  return {
    enabled,
    month,
    title: "Defi Proxiplay",
    description: "",
    target_days: targetDays,
    prize_title: "Un resto pour 2",
    prize_description: "Bon cadeau restaurant",
    prize_value: 120,
    image_url: "",
    draw_date: timestampFromIso(drawDate),
  };
}

test.beforeEach(async () => {
  await clearFirestore();
});

test("premiere participation de la journee -> +1", async () => {
  await seedConfig();
  await seedUser("u1");

  await track("u1", buildIsoDay("2026-08", 1));

  const state = await getState("u1");
  assert.equal(state.active_days_count, 1);
  assert.deepEqual(state.active_dates, ["2026-08-01"]);
  assert.equal(state.qualified, false);
});

test("deux challenges actifs -> une participation incremente les deux", async () => {
  await seedChallenge({type: "attendance", targetDays: 10});
  await seedChallenge({type: "restaurant", targetDays: 15});
  await seedUser("u1");

  await trackAll("u1", buildIsoDay("2026-08", 1));

  const attendance = await getState("u1", "2026-08");
  const restaurant = await getState("u1", "restaurant_2026-08");
  assert.equal(attendance.active_days_count, 1);
  assert.equal(restaurant.active_days_count, 1);
  assert.equal(attendance.target_days, 10);
  assert.equal(restaurant.target_days, 15);
});

test("deux challenges actifs -> seconde participation du jour n incremente aucun", async () => {
  await seedChallenge({type: "attendance", targetDays: 10});
  await seedChallenge({type: "restaurant", targetDays: 15});
  await seedUser("u1");

  await trackAll("u1", buildIsoDay("2026-08", 1));
  await trackAll("u1", "2026-08-01T18:00:00.000Z");

  const attendance = await getState("u1", "2026-08");
  const restaurant = await getState("u1", "restaurant_2026-08");
  assert.equal(attendance.active_days_count, 1);
  assert.equal(restaurant.active_days_count, 1);
});

test("tirages attendance et restaurant restent independants", async () => {
  await seedChallenge({
    type: "attendance",
    month: "2026-07",
    targetDays: 1,
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedChallenge({
    type: "restaurant",
    month: "2026-07",
    targetDays: 1,
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("u1");
  await trackAll("u1", buildIsoDay("2026-07", 1));

  const attendanceResult = await drawWinnerForMonthlyChallenge({
    ...buildConfigForDraw({month: "2026-07", targetDays: 1}),
    challenge_id: "2026-07",
    type: "attendance",
  }, "test-attendance");
  const restaurantResult = await drawWinnerForMonthlyChallenge({
    ...buildConfigForDraw({month: "2026-07", targetDays: 1}),
    challenge_id: "restaurant_2026-07",
    type: "restaurant",
    restaurant_name: "La Cocotte",
  }, "test-restaurant");

  assert.equal(attendanceResult.status, "completed");
  assert.equal(restaurantResult.status, "completed");
  assert.notEqual(attendanceResult.prizeId, restaurantResult.prizeId);
  const prizesSnap = await firestore.collection("prizes").get();
  assert.equal(prizesSnap.size, 2);
});

test("deuxieme participation le meme jour -> aucun increment", async () => {
  await seedConfig();
  await seedUser("u1");

  await track("u1", buildIsoDay("2026-08", 1));
  await track("u1", "2026-08-01T18:00:00.000Z");

  const state = await getState("u1");
  assert.equal(state.active_days_count, 1);
  assert.deepEqual(state.active_dates, ["2026-08-01"]);
});

test("participation le lendemain -> +1", async () => {
  await seedConfig();
  await seedUser("u1");

  await track("u1", buildIsoDay("2026-08", 1));
  await track("u1", buildIsoDay("2026-08", 2));

  const state = await getState("u1");
  assert.equal(state.active_days_count, 2);
  assert.deepEqual(state.active_dates, ["2026-08-01", "2026-08-02"]);
});

test("14 jours -> non qualifie", async () => {
  await seedConfig();
  await seedUser("u1");

  for (let day = 1; day <= 14; day += 1) {
    await track("u1", buildIsoDay("2026-08", day));
  }

  const state = await getState("u1");
  assert.equal(state.active_days_count, 14);
  assert.equal(state.qualified, false);
});

test("15e jour -> qualification", async () => {
  await seedConfig();
  await seedUser("u1");

  for (let day = 1; day <= 15; day += 1) {
    await track("u1", buildIsoDay("2026-08", day));
  }

  const state = await getState("u1");
  const entrySnap = await firestore
    .collection("monthly_challenge_entries")
    .doc("2026-08_u1")
    .get();

  assert.equal(state.active_days_count, 15);
  assert.equal(state.qualified, true);
  assert.equal(state.draw_entry_created, true);
  assert.equal(entrySnap.exists, true);
});

test("16e jour -> toujours une seule entree au tirage", async () => {
  await seedConfig();
  await seedUser("u1");

  for (let day = 1; day <= 16; day += 1) {
    await track("u1", buildIsoDay("2026-08", day));
  }

  const state = await getState("u1");
  const entriesSnap = await firestore
    .collection("monthly_challenge_entries")
    .where("month", "==", "2026-08")
    .where("uid", "==", "u1")
    .get();

  assert.equal(state.active_days_count, 16);
  assert.equal(entriesSnap.size, 1);
});

test("double appel simultane -> aucun double comptage", async () => {
  await seedConfig();
  await seedUser("u1");

  await Promise.all([
    track("u1", buildIsoDay("2026-08", 1)),
    track("u1", buildIsoDay("2026-08", 1)),
  ]);

  const state = await getState("u1");
  assert.equal(state.active_days_count, 1);
  assert.deepEqual(state.active_dates, ["2026-08-01"]);
});

test("changement de mois -> nouveau compteur", async () => {
  await seedConfig({month: "2026-08"});
  await seedUser("u1");

  await track("u1", buildIsoDay("2026-08", 31));

  await seedConfig({
    month: "2026-09",
    drawDate: "2026-10-01T09:00:00.000Z",
  });
  await track("u1", "2026-09-01T10:00:00.000Z");

  const augustState = await getState("u1", "2026-08");
  const septemberState = await getState("u1", "2026-09");

  assert.equal(augustState.active_days_count, 1);
  assert.equal(septemberState.active_days_count, 1);
  assert.deepEqual(septemberState.active_dates, ["2026-09-01"]);
});

test("utilisateur non qualifie exclu du tirage", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("qualified-user");
  await seedUser("not-qualified-user");

  for (let day = 1; day <= 15; day += 1) {
    await track("qualified-user", buildIsoDay("2026-07", day));
  }
  for (let day = 1; day <= 14; day += 1) {
    await track("not-qualified-user", buildIsoDay("2026-07", day));
  }

  const result = await drawWinnerForMonthlyChallenge(buildConfigForDraw(), "test");

  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "qualified-user");
});

test("utilisateur qualifie present une seule fois", async () => {
  await seedConfig();
  await seedUser("u1");

  for (let day = 1; day <= 17; day += 1) {
    await track("u1", buildIsoDay("2026-08", day));
  }

  const entriesSnap = await firestore
    .collection("monthly_challenge_entries")
    .where("month", "==", "2026-08")
    .where("uid", "==", "u1")
    .get();

  assert.equal(entriesSnap.size, 1);
});

test("double declenchement du tirage -> aucun second gagnant", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("u1");
  await seedUser("u2");

  for (let day = 1; day <= 15; day += 1) {
    await track("u1", buildIsoDay("2026-07", day));
    await track("u2", buildIsoDay("2026-07", day));
  }

  const config = buildConfigForDraw();
  const firstResult = await drawWinnerForMonthlyChallenge(config, "test-first");
  const secondResult = await drawWinnerForMonthlyChallenge(config, "test-second");
  const drawSnap = await firestore.collection("monthly_challenge_draws").doc("2026-07").get();
  const drawData = drawSnap.data() || {};

  assert.equal(firstResult.status, "completed");
  assert.equal(secondResult.status, "already_completed");
  assert.equal(drawData.status, "completed");
  assert.equal(drawData.winner_uid, firstResult.winnerUid);
});

test("changement de target_days apres demarrage ne retro-qualifie pas", async () => {
  await seedConfig({month: "2026-08", targetDays: 15});
  await seedUser("u1");

  for (let day = 1; day <= 10; day += 1) {
    await track("u1", buildIsoDay("2026-08", day));
  }

  await seedConfig({month: "2026-08", targetDays: 12});

  const state = await getState("u1", "2026-08");
  const response = buildChallengeStateResponse(
    buildConfigForDraw({
      month: "2026-08",
      targetDays: 12,
      drawDate: "2026-10-01T09:00:00.000Z",
    }),
    state,
  );

  assert.equal(state.target_days, 15);
  assert.equal(response.targetDays, 15);
  assert.equal(response.qualified, false);
  assert.equal(response.remainingDays, 5);
});

test("tirage avant draw_date refuse", async () => {
  await seedConfig({
    month: "2026-08",
    drawDate: "2026-10-01T09:00:00.000Z",
  });
  await seedUser("u1");

  await assert.rejects(
    () => drawWinnerForMonthlyChallenge(buildConfigForDraw({
      month: "2026-08",
      drawDate: "2026-10-01T09:00:00.000Z",
    }), "too-early"),
    (error) => error.code === "failed-precondition",
  );
});

test("defi desactive refuse", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
    enabled: false,
  });

  await assert.rejects(
    () => drawWinnerForMonthlyChallenge(buildConfigForDraw({
      enabled: false,
    }), "disabled"),
    (error) => error.code === "failed-precondition",
  );
});

test("aucun qualifie -> statut final sans second tirage", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("u1");

  for (let day = 1; day <= 14; day += 1) {
    await track("u1", buildIsoDay("2026-07", day));
  }

  const firstResult = await drawWinnerForMonthlyChallenge(buildConfigForDraw(), "none");
  const secondResult = await drawWinnerForMonthlyChallenge(buildConfigForDraw(), "none-again");

  assert.equal(firstResult.status, "no_eligible_users");
  assert.equal(secondResult.status, "already_finalized");
});

test("utilisateur supprime exclu du tirage", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("deleted-user", {auto_deleted: true});
  await seedUser("active-user");

  for (let day = 1; day <= 15; day += 1) {
    await track("deleted-user", buildIsoDay("2026-07", day));
    await track("active-user", buildIsoDay("2026-07", day));
  }

  const result = await drawWinnerForMonthlyChallenge(buildConfigForDraw(), "deleted-check");
  const deletedEntry = await firestore
    .collection("monthly_challenge_entries")
    .doc("2026-07_deleted-user")
    .get();

  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "active-user");
  assert.equal(deletedEntry.data()?.status, "excluded_deleted_account");
});

test("utilisateur suspendu exclu selon player_status_cached", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("suspended-user", {player_status_cached: "suspendu"});
  await seedUser("active-user");

  for (let day = 1; day <= 15; day += 1) {
    await track("suspended-user", buildIsoDay("2026-07", day));
    await track("active-user", buildIsoDay("2026-07", day));
  }

  const result = await drawWinnerForMonthlyChallenge(buildConfigForDraw(), "status-check");
  const suspendedEntry = await firestore
    .collection("monthly_challenge_entries")
    .doc("2026-07_suspended-user")
    .get();

  assert.equal(result.winnerUid, "active-user");
  assert.equal(suspendedEntry.data()?.status, "excluded_player_status");
});

test("deux tirages concurrents ne creent ni double lot ni double my_lots", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("u1");
  await seedUser("u2");

  for (let day = 1; day <= 15; day += 1) {
    await track("u1", buildIsoDay("2026-07", day));
    await track("u2", buildIsoDay("2026-07", day));
  }

  const [resultA, resultB] = await Promise.all([
    drawWinnerForMonthlyChallenge(buildConfigForDraw(), "parallel-a"),
    drawWinnerForMonthlyChallenge(buildConfigForDraw(), "parallel-b"),
  ]);

  const completedResult = [resultA, resultB].find((result) => result.status === "completed");
  assert.ok(completedResult);

  const prizesSnap = await firestore.collection("prizes").get();
  const myLotsSnap = await firestore
    .collection("users")
    .doc(completedResult.winnerUid)
    .collection("my_lots")
    .get();

  assert.equal(prizesSnap.size, 1);
  assert.equal(myLotsSnap.size, 1);
});

test("notification de qualification envoyee une seule fois", async () => {
  await queueMonthlyChallengeNotifications("u1", [
    {
      key: "qualified",
      title: "Tu es qualifie !",
      body: "Tu participes maintenant au tirage.",
    },
  ], "2026-08");

  await queueMonthlyChallengeNotifications("u1", [
    {
      key: "qualified",
      title: "Tu es qualifie !",
      body: "Tu participes maintenant au tirage.",
    },
  ], "2026-08");

  const docs = await getNotificationDocs();
  assert.equal(docs.length, 1);
});

test("timezone Europe/Paris autour de minuit -> deux jours distincts", async () => {
  await seedConfig({
    month: "2026-07",
    drawDate: "2026-08-01T09:00:00.000Z",
  });
  await seedUser("u1");

  await track("u1", "2026-07-01T21:30:00.000Z");
  await track("u1", "2026-07-01T22:30:00.000Z");

  const state = await getState("u1", "2026-07");
  assert.equal(state.active_days_count, 2);
  assert.deepEqual(state.active_dates, ["2026-07-01", "2026-07-02"]);
});

test("stats admin -> 0 participant", async () => {
  const stats = computeMonthlyChallengeStats(buildConfigForDraw({
    month: "2026-09",
    drawDate: "2026-10-01T09:00:00.000Z",
  }), []);

  assert.equal(stats.startedCount, 0);
  assert.equal(stats.qualifiedCount, 0);
  assert.equal(stats.qualificationRate, 0);
  assert.equal(stats.averageActiveDays, 0);
  assert.equal(stats.timeline.length, 30);
});

test("stats admin -> moyenne, taux et mediane", async () => {
  const stats = computeMonthlyChallengeStats(
    buildConfigForDraw({
      month: "2026-09",
      drawDate: "2026-10-01T09:00:00.000Z",
      targetDays: 15,
    }),
    [
      {
        active_days_count: 3,
        active_dates: ["2026-09-01", "2026-09-03", "2026-09-04"],
        qualified: false,
      },
      {
        active_days_count: 9,
        active_dates: ["2026-09-02", "2026-09-05"],
        qualified: false,
      },
      {
        active_days_count: 15,
        active_dates: ["2026-09-01", "2026-09-15"],
        qualified: true,
        qualified_at: timestampFromIso("2026-09-15T10:00:00.000Z"),
      },
    ],
  );

  assert.equal(stats.startedCount, 3);
  assert.equal(stats.qualifiedCount, 1);
  assert.equal(stats.qualificationRate, 33.3);
  assert.equal(stats.averageActiveDays, 9);
  assert.equal(stats.medianActiveDays, 9);
});

test("stats admin -> distribution correcte pour target_days 15", async () => {
  const stats = computeMonthlyChallengeStats(
    buildConfigForDraw({
      month: "2026-09",
      drawDate: "2026-10-01T09:00:00.000Z",
      targetDays: 15,
    }),
    [
      {active_days_count: 1, active_dates: ["2026-09-01"]},
      {active_days_count: 4, active_dates: ["2026-09-02"]},
      {active_days_count: 8, active_dates: ["2026-09-03"]},
      {active_days_count: 11, active_dates: ["2026-09-04"]},
      {active_days_count: 14, active_dates: ["2026-09-05"]},
      {active_days_count: 15, active_dates: ["2026-09-06"], qualified: true},
    ],
  );

  assert.deepEqual(
    stats.distribution.map((bucket) => ({
      label: bucket.label,
      count: bucket.count,
    })),
    [
      {label: "1-3", count: 1},
      {label: "4-6", count: 1},
      {label: "7-9", count: 1},
      {label: "10-12", count: 1},
      {label: "13-14", count: 1},
      {label: "15+", count: 1},
    ],
  );
});

test("stats admin -> active_days_count manquant ou invalide", async () => {
  const stats = computeMonthlyChallengeStats(
    buildConfigForDraw({
      month: "2026-09",
      drawDate: "2026-10-01T09:00:00.000Z",
    }),
    [
      {active_dates: ["2026-09-01", "2026-09-02"]},
      {active_days_count: "abc", active_dates: ["2026-09-03"]},
    ],
  );

  assert.equal(stats.startedCount, 2);
  assert.equal(stats.averageActiveDays, 1.5);
});

test("stats admin -> gagnant existant et statut du tirage", async () => {
  const stats = computeMonthlyChallengeStats(
    buildConfigForDraw({
      month: "2026-09",
      drawDate: "2026-10-01T09:00:00.000Z",
    }),
    [
      {
        active_days_count: 15,
        active_dates: ["2026-09-01", "2026-09-15"],
        qualified: true,
      },
    ],
    {
      status: "completed",
      eligible_count: 12,
      winner_uid: "winner-42",
      drawn_at: timestampFromIso("2026-10-01T09:05:00.000Z"),
    },
  );

  assert.equal(stats.drawStatus, "completed");
  assert.equal(stats.eligibleCount, 12);
  assert.equal(stats.winnerUid, "winner-42");
  assert.ok(stats.drawnAt);
});

test("stats admin -> mois sans defi", async () => {
  const stats = computeMonthlyChallengeStats(
    {
      enabled: false,
      month: "",
      target_days: 15,
    },
    [],
  );

  assert.equal(stats.month, "");
  assert.equal(stats.startedCount, 0);
  assert.deepEqual(stats.timeline, []);
});
