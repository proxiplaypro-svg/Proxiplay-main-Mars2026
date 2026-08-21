"use strict";

function isFunctionsEmulator() {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

function getEmulatorNowDate() {
  if (!isFunctionsEmulator()) {
    return new Date();
  }

  const raw = (process.env.EMULATOR_TEST_DATE || "").trim();
  if (!raw) {
    return new Date();
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    throw new Error("EMULATOR_TEST_DATE must use YYYY-MM-DD.");
  }
  const parsed = new Date(`${raw}T12:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) {
    throw new Error("EMULATOR_TEST_DATE is not a valid calendar date.");
  }
  return parsed;
}

function getNowTimestamp(admin) {
  return admin.firestore.Timestamp.fromDate(getEmulatorNowDate());
}

module.exports = {
  getEmulatorNowDate,
  getNowTimestamp,
  isFunctionsEmulator,
};
