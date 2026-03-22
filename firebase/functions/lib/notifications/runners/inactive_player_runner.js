const {
  kAutomationTypeInactivePlayer,
  kFcmTokensCollection,
  kNotificationChannelPush,
} = require("../constants");
const {
  getActiveAutomationById,
} = require("../automation_repository");
const {
  getDeliveryState,
  isInCooldown,
  markDeliveryStateSent,
} = require("../delivery_state_repository");
const {
  finishAutomationRun,
  startAutomationRun,
} = require("../automation_logger");
const {enqueueUserPushNotification} = require("../push_queue");
const {
  getInactivePlayerFrequency,
  getInactivePlayerMessage,
  getInactivePlayerRemainingPartsOnly,
  getInactivePlayerSendHour,
  getInactiveStatusesFromAutomation,
  getTrimmedString,
  normalizeLimit,
  normalizeUserIds,
  toBoolean,
} = require("../utils");

async function runInactivePlayerAutomation({
  firestore,
  admin,
  automationId,
  dryRun = true,
  onlyUserIds = [],
  limit = 0,
  trigger = "manual_callable",
}) {
  const automation = await getActiveAutomationById(firestore, automationId);
  if (!automation) {
    throw new Error(
      `inactive_player automation not found or inactive: ${automationId}`,
    );
  }

  if (automation.data.type !== kAutomationTypeInactivePlayer) {
    throw new Error(
      `automation ${automationId} is not of type ${kAutomationTypeInactivePlayer}`,
    );
  }

  const normalizedOnlyUserIds = normalizeUserIds(onlyUserIds);
  const onlyUserIdsSet =
    normalizedOnlyUserIds.length > 0 ? new Set(normalizedOnlyUserIds) : null;
  const normalizedLimit = normalizeLimit(limit, 0, 500);
  const frequency = getInactivePlayerFrequency(automation.data);
  const sendHour = getInactivePlayerSendHour(automation.data);
  const remainingPartsOnly = getInactivePlayerRemainingPartsOnly(automation.data);
  const targetStatuses = getInactiveStatusesFromAutomation(automation.data);
  const cooldownDays = Math.max(
    0,
    Number.isFinite(Number(automation.data.cooldownDays))
      ? Number(automation.data.cooldownDays)
      : 0,
  );
  const cooldownMs = cooldownDays * 24 * 60 * 60 * 1000;
  const nowMs = Date.now();

  const {runId, runRef} = await startAutomationRun({
    firestore,
    admin,
    automation,
    trigger,
    dryRun: toBoolean(dryRun, true),
    onlyUserIds: normalizedOnlyUserIds,
    limit: normalizedLimit,
  });

  const summary = {
    automationId: automation.id,
    dryRun: toBoolean(dryRun, true),
    config: {
      frequency,
      sendHour,
      remainingPartsOnly,
    },
    matchedUsers: 0,
    eligibleUsers: 0,
    queuedNotifications: 0,
    skippedCooldown: 0,
    skippedNoToken: 0,
    skippedByOnlyUserIds: 0,
    errors: 0,
  };

  try {
    const usersSnap = await firestore
      .collection("users")
      .where("user_role", "==", "joueur")
      .where("player_status_cached", "in", targetStatuses)
      .get();

    summary.matchedUsers = usersSnap.size;

    let processedEligible = 0;
    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data() || {};
      const userId = getTrimmedString(userData.uid) || userDoc.id;
      if (!userId) {
        summary.errors += 1;
        continue;
      }

      if (onlyUserIdsSet && !onlyUserIdsSet.has(userId)) {
        summary.skippedByOnlyUserIds += 1;
        continue;
      }

      if (normalizedLimit > 0 && processedEligible >= normalizedLimit) {
        break;
      }

      if (remainingPartsOnly) {
        const remainingParts = Number(userData.remaining_part);
        if (!Number.isFinite(remainingParts) || remainingParts <= 0) {
          continue;
        }
      }

      const deliveryState = await getDeliveryState(
        firestore,
        automation.id,
        userId,
        kNotificationChannelPush,
      );
      if (isInCooldown(deliveryState.data, cooldownMs, nowMs)) {
        summary.skippedCooldown += 1;
        continue;
      }

      const tokensSnap = await firestore
        .collection("users")
        .doc(userId)
        .collection(kFcmTokensCollection)
        .limit(1)
        .get();
      if (tokensSnap.empty) {
        summary.skippedNoToken += 1;
        continue;
      }

      processedEligible += 1;
      summary.eligibleUsers += 1;

      if (!summary.dryRun) {
        const status = getTrimmedString(userData.player_status_cached) || "default";
        const message = getInactivePlayerMessage(status, automation.data);
        const notificationDocId = `${automation.id}_${userId}_${runId}`;
        const queued = await enqueueUserPushNotification({
          firestore,
          admin,
          docId: notificationDocId,
          title: message.title,
          body: message.body,
          userId,
          createdBy: `system/notification_automation/${automation.id}`,
        });

        if (!queued) {
          summary.errors += 1;
          continue;
        }

        await markDeliveryStateSent({
          admin,
          firestore,
          automationId: automation.id,
          userId,
          runId,
          notificationDocId,
          status: "queued",
          exists: deliveryState.exists,
        });
        summary.queuedNotifications += 1;
      }
    }

    await finishAutomationRun({
      admin,
      runRef,
      summary,
    });
    return summary;
  } catch (error) {
    summary.errors += 1;
    await finishAutomationRun({
      admin,
      runRef,
      summary,
      errorMessage: error.message || String(error),
    });
    throw error;
  }
}

module.exports = {
  runInactivePlayerAutomation,
};
