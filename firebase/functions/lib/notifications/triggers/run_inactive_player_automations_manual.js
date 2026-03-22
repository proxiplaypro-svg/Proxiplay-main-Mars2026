const {runInactivePlayerAutomation} = require("../runners/inactive_player_runner");
const {
  normalizeLimit,
  normalizeUserIds,
  toBoolean,
  getTrimmedString,
} = require("../utils");

function createRunInactivePlayerAutomationsManual({
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

    const automationId = getTrimmedString(data && data.automationId);
    if (!automationId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "automationId is required.",
      );
    }

    const dryRun = toBoolean(data && data.dryRun, true);
    const onlyUserIds = normalizeUserIds(data && data.onlyUserIds);
    const limit = normalizeLimit(data && data.limit, 0, 500);

    try {
      return await runInactivePlayerAutomation({
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
        error.message || "Unable to run inactive player automation.",
      );
    }
  });
}

module.exports = {
  createRunInactivePlayerAutomationsManual,
};
