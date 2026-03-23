const {listActiveAutomationsByType} = require("../automation_repository");
const {
  kAutomationTypeBirthday,
  kParisTimeZone,
} = require("../constants");
const {runBirthdayAutomation, getBirthdaySendHour} = require("../runners/birthday_runner");

function getCurrentHourInTimeZone(date, timeZone) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    hour: "2-digit",
    hour12: false,
  }).formatToParts(date);
  return Number(parts.find((part) => part.type === "hour").value);
}

function createRunBirthdayAutomationsDaily({
  functions,
  firestore,
  admin,
}) {
  return functions.pubsub
    .schedule("0 * * * *")
    .timeZone(kParisTimeZone)
    .onRun(async () => {
      const currentHour = getCurrentHourInTimeZone(new Date(), kParisTimeZone);
      const automations = await listActiveAutomationsByType(
        firestore,
        kAutomationTypeBirthday,
      );

      for (const automation of automations) {
        if (getBirthdaySendHour(automation.data) !== currentHour) {
          continue;
        }

        await runBirthdayAutomation({
          firestore,
          admin,
          automationId: automation.id,
          dryRun: false,
          trigger: "scheduled_hourly",
        });
      }

      return null;
    });
}

module.exports = {
  createRunBirthdayAutomationsDaily,
};
