const {
  kNotificationAutomationsCollection,
  kNotificationDeliveryStateCollection,
  kRunsSubcollection,
} = require("./constants");

function getAutomationCollection(firestore) {
  return firestore.collection(kNotificationAutomationsCollection);
}

function getAutomationRef(firestore, automationId) {
  return getAutomationCollection(firestore).doc(automationId);
}

function getAutomationRunsCollection(firestore, automationId) {
  return getAutomationRef(firestore, automationId).collection(kRunsSubcollection);
}

function getAutomationRunRef(firestore, automationId, runId) {
  return getAutomationRunsCollection(firestore, automationId).doc(runId);
}

function buildDeliveryStateDocId(automationId, userId, channel) {
  return `${automationId}__${userId}__${channel}`;
}

function getDeliveryStateCollection(firestore) {
  return firestore.collection(kNotificationDeliveryStateCollection);
}

function getDeliveryStateRef(firestore, automationId, userId, channel) {
  return getDeliveryStateCollection(firestore).doc(
    buildDeliveryStateDocId(automationId, userId, channel),
  );
}

module.exports = {
  buildDeliveryStateDocId,
  getAutomationCollection,
  getAutomationRef,
  getAutomationRunRef,
  getAutomationRunsCollection,
  getDeliveryStateCollection,
  getDeliveryStateRef,
};
