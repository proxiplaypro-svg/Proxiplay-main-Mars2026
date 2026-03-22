const {
  kNotificationChannelPush,
} = require("./constants");
const {getDeliveryStateRef} = require("./firestore_paths");
const {timestampToMillis} = require("./utils");

async function getDeliveryState(firestore, automationId, userId, channel = kNotificationChannelPush) {
  const ref = getDeliveryStateRef(firestore, automationId, userId, channel);
  const snap = await ref.get();
  return {
    ref,
    exists: snap.exists,
    data: snap.exists ? snap.data() || {} : {},
  };
}

function isInCooldown(deliveryStateData, cooldownMs, nowMs) {
  if (!deliveryStateData || cooldownMs <= 0) {
    return false;
  }
  const lastSentAtMs = timestampToMillis(deliveryStateData.lastSentAt);
  if (lastSentAtMs === null) {
    return false;
  }
  return nowMs - lastSentAtMs < cooldownMs;
}

async function markDeliveryStateSent({
  admin,
  firestore,
  automationId,
  userId,
  runId,
  notificationDocId,
  channel = kNotificationChannelPush,
  status,
  exists = false,
  extra = {},
}) {
  const ref = getDeliveryStateRef(firestore, automationId, userId, channel);
  await ref.set(
    {
      automationId,
      userId,
      channel,
      lastRunId: runId,
      lastNotificationDocId: notificationDocId || "",
      lastStatus: status || "queued",
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(exists ? {} : {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...extra,
    },
    {merge: true},
  );
}

module.exports = {
  getDeliveryState,
  isInCooldown,
  markDeliveryStateSent,
};
