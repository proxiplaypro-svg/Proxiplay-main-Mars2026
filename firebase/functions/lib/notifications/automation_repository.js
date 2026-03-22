const {
  kAutomationTypeInactivePlayer,
} = require("./constants");
const {
  getAutomationCollection,
  getAutomationRef,
  getAutomationRunRef,
} = require("./firestore_paths");

async function getActiveAutomationById(firestore, automationId) {
  const snap = await getAutomationRef(firestore, automationId).get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() || {};
  if (data.type !== kAutomationTypeInactivePlayer || data.isActive !== true) {
    return null;
  }
  return {
    id: snap.id,
    ref: snap.ref,
    data,
  };
}

async function listActiveAutomationsByType(firestore, type) {
  const snap = await getAutomationCollection(firestore)
    .where("type", "==", type)
    .where("isActive", "==", true)
    .get();

  return snap.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data() || {},
  }));
}

async function createAutomationRun({
  firestore,
  admin,
  automationId,
  payload,
}) {
  const ref = getAutomationRunRef(
    firestore,
    automationId,
    payload.runId || getAutomationCollection(firestore).doc().id,
  );

  await ref.set({
    ...payload,
    status: payload.status || "started",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return ref;
}

async function updateAutomationRun({
  runRef,
  admin,
  patch,
}) {
  await runRef.set(
    {
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

module.exports = {
  createAutomationRun,
  getActiveAutomationById,
  listActiveAutomationsByType,
  updateAutomationRun,
};
