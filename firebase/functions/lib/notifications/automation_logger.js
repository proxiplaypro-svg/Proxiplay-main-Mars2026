const {
  createAutomationRun,
  updateAutomationRun,
} = require("./automation_repository");

async function startAutomationRun({
  firestore,
  admin,
  automation,
  trigger,
  dryRun,
  onlyUserIds,
  limit,
}) {
  const runId = automation.ref.collection("runs").doc().id;
  const runRef = await createAutomationRun({
    firestore,
    admin,
    automationId: automation.id,
    payload: {
      runId,
      automationId: automation.id,
      automationType: automation.data.type,
      trigger,
      dryRun,
      status: "started",
      onlyUserIds,
      limit,
    },
  });

  return {runId, runRef};
}

async function finishAutomationRun({
  admin,
  runRef,
  summary,
  errorMessage = "",
}) {
  await updateAutomationRun({
    runRef,
    admin,
    patch: {
      status: errorMessage ? "failed" : "completed",
      errorMessage,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      dryRun: summary && summary.dryRun === true,
      summary,
    },
  });
}

module.exports = {
  finishAutomationRun,
  startAutomationRun,
};
