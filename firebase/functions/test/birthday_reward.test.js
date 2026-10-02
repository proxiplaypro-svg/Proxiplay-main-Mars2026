const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildBirthdayNotificationDocId,
  buildLegacyBirthdayNotificationDocId,
  getBirthdayDateKey,
  getBirthdayMessage,
  getBirthdayRewardConfig,
  grantBirthdayReward,
  isLegacyBirthdayDeliveryProcessedToday,
} = require("../lib/notifications/runners/birthday_runner");
const {kDefaultBirthdayMessage} = require("../lib/notifications/constants");

function createFakeFirestore(initialRemainingPart) {
  const users = new Map([["player-1", {remaining_part: initialRemainingPart}]]);
  const rewards = new Map();

  const userRef = (id) => ({kind: "user", id, path: `users/${id}`});
  const rewardRef = (id) => ({kind: "reward", id, path: `reward_events/${id}`});
  const snapshot = (value) => ({
    exists: value !== undefined,
    data: () => value,
  });

  return {
    collection(name) {
      if (name === "users") return {doc: userRef};
      if (name === "reward_events") return {doc: rewardRef};
      throw new Error(`Unexpected collection: ${name}`);
    },
    async runTransaction(callback) {
      const updates = [];
      const creates = [];
      const transaction = {
        get: async (ref) => snapshot(ref.kind === "user" ? users.get(ref.id) : rewards.get(ref.id)),
        update: (ref, data) => updates.push({ref, data}),
        create: (ref, data) => creates.push({ref, data}),
      };
      const result = await callback(transaction);
      updates.forEach(({ref, data}) => users.set(ref.id, {...users.get(ref.id), ...data}));
      creates.forEach(({ref, data}) => rewards.set(ref.id, data));
      return result;
    },
    userRef: userRef("player-1"),
    users,
    rewards,
  };
}

const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => "SERVER_TIMESTAMP",
    },
  },
};

async function grant(firestore, birthdayDateKey = "2026-10-02") {
  return grantBirthdayReward({
    firestore,
    admin,
    automationId: "birthday",
    userId: "player-1",
    userRef: firestore.userRef,
    birthdayDateKey,
    rewardConfig: {type: "birthday_play_credit", value: 3, grantedBy: "birthday"},
  });
}

for (const [remainingPart, expected] of [[3, 6], [2, 5], [0, 3], [6, 9]]) {
  test(`birthday credit atomically adds three plays to ${remainingPart}`, async () => {
    const firestore = createFakeFirestore(remainingPart);
    const result = await grant(firestore);
    assert.equal(result.alreadyExisted, false);
    assert.equal(firestore.users.get("player-1").remaining_part, expected);
    assert.equal(firestore.rewards.get("birthday__player-1__2026-10-02").value, 3);
  });
}

test("birthday credit is idempotent for the same annual date", async () => {
  const firestore = createFakeFirestore(3);
  await grant(firestore);
  const retry = await grant(firestore);
  assert.equal(retry.alreadyExisted, true);
  assert.equal(firestore.users.get("player-1").remaining_part, 6);
});

test("a new annual date grants a new birthday credit without colliding with legacy MM-DD events", async () => {
  const firestore = createFakeFirestore(3);
  firestore.rewards.set("birthday__player-1__10-02", {
    status: "granted",
    createdAt: new Date("2025-10-02T09:00:00.000Z"),
  });
  await grant(firestore, "2026-10-02");
  await grant(firestore, "2027-10-02");
  assert.equal(firestore.users.get("player-1").remaining_part, 9);
  assert.ok(firestore.rewards.has("birthday__player-1__2026-10-02"));
  assert.ok(firestore.rewards.has("birthday__player-1__2027-10-02"));
});

test("a legacy reward created today blocks only the transition-day duplicate credit", async () => {
  const firestore = createFakeFirestore(3);
  firestore.rewards.set("birthday__player-1__10-02", {
    status: "granted",
    createdAt: new Date("2026-10-02T09:00:00.000Z"),
  });
  const result = await grant(firestore);
  assert.equal(result.alreadyExisted, true);
  assert.equal(result.legacyAlreadyProcessed, true);
  assert.equal(firestore.users.get("player-1").remaining_part, 3);
  assert.equal(firestore.rewards.has("birthday__player-1__2026-10-02"), false);
});

test("annual birthday keys use Europe/Paris calendar dates", () => {
  assert.equal(getBirthdayDateKey(new Date("2026-10-02T00:30:00.000Z")), "2026-10-02");
  assert.equal(
    buildBirthdayNotificationDocId("birthday", "player-1", "2026-10-02"),
    "birthday_player-1_20261002",
  );
  assert.equal(
    buildLegacyBirthdayNotificationDocId("birthday", "player-1", "10-02"),
    "birthday_player-1_1002",
  );
  assert.equal(
    isLegacyBirthdayDeliveryProcessedToday(
      {birthdayDateKey: "10-02", lastSentAt: new Date("2026-10-02T09:00:00.000Z")},
      "2026-10-02",
    ),
    true,
  );
});

test("birthday automation uses the explicit credit and safely upgrades its legacy config", () => {
  assert.deepEqual(
    getBirthdayRewardConfig({reward: {type: "birthday_play_credit", value: 3, grantedBy: "birthday"}}),
    {type: "birthday_play_credit", value: 3, grantedBy: "birthday"},
  );
  assert.deepEqual(
    getBirthdayRewardConfig({reward: {type: "all_games_until_midnight", value: 1, grantedBy: "birthday"}}),
    {type: "birthday_play_credit", value: 3, grantedBy: "birthday"},
  );
});

test("birthday notification copy announces the real three-play credit", () => {
  assert.match(kDefaultBirthdayMessage.title, /\{firstName\}/);
  assert.match(kDefaultBirthdayMessage.body, /3 parties supplémentaires/);
});

test("legacy birthday copy is upgraded in memory while custom copy remains supported", () => {
  const upgraded = getBirthdayMessage({
    messagesByStatus: {
      default: {
        title: "Joyeux anniversaire {firstName} 🎉",
        body: "Profitez de vos avantages du jour et tentez votre chance !",
      },
    },
  }, {first_name: "Marie"});
  assert.equal(upgraded.title, "Joyeux anniversaire Marie 🎉");
  assert.match(upgraded.body, /3 parties supplémentaires/);

  const custom = getBirthdayMessage({
    messagesByStatus: {default: {title: "Titre personnalisé", body: "Texte personnalisé"}},
  }, {first_name: "Marie"});
  assert.deepEqual(custom, {title: "Titre personnalisé", body: "Texte personnalisé"});
});
