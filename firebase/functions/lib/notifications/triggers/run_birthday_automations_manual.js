const {runBirthdayAutomation} = require("../runners/birthday_runner");
const {
  normalizeLimit,
  normalizeUserIds,
  toBoolean,
  getTrimmedString,
} = require("../utils");

function createRunBirthdayAutomationsManual({
  functions,
  firestore,
  admin,
  assertIsAdmin,
}) {
  return functions.https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }

    try {
      await assertIsAdmin(context.auth.uid);
    } catch (_) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Admin role required.",
      );
    }

    const automationId = getTrimmedString(data && data.automationId) || "birthday";
    const dryRun = toBoolean(data && data.dryRun, true);
    const onlyUserIds = normalizeUserIds(data && data.onlyUserIds);
    const limit = normalizeLimit(data && data.limit, 0, 500);

    try {
      return await runBirthdayAutomation({
        firestore,
        admin,
        automationId,
        dryRun,
        onlyUserIds,
        limit,
        trigger: "manual_callable",
      });
    } catch (error) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        error.message || "Unable to run birthday automation.",
      );
    }
  });
}

module.exports = {
  createRunBirthdayAutomationsManual,
};
