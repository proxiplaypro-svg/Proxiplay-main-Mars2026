const {
  kAutomationTypeBirthday,
  kDefaultBirthdayMessage,
  kFcmTokensCollection,
  kNotificationChannelEmail,
  kNotificationChannelPush,
  kParisTimeZone,
} = require("../constants");
const {
  getActiveAutomationByIdAndType,
} = require("../automation_repository");
const {
  getDeliveryState,
  markDeliveryStateSent,
} = require("../delivery_state_repository");
const {
  finishAutomationRun,
  startAutomationRun,
} = require("../automation_logger");
const {sendTextEmail} = require("../email_sender");
const {enqueueUserPushNotification} = require("../push_queue");
const {
  getTrimmedString,
  normalizeLimit,
  normalizeUserIds,
  timestampToMillis,
  toBoolean,
} = require("../utils");

function getTimeZoneDateParts(date, timeZone) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(date);

  return {
    year: Number(parts.find((part) => part.type === "year").value),
    month: Number(parts.find((part) => part.type === "month").value),
    day: Number(parts.find((part) => part.type === "day").value),
    hour: Number(parts.find((part) => part.type === "hour").value),
  };
}

function getTimeZoneOffsetMillis(date, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    timeZoneName: "shortOffset",
  });
  const offsetPart = formatter
    .formatToParts(date)
    .find((part) => part.type === "timeZoneName");
  const match = String(offsetPart && offsetPart.value)
    .match(/GMT([+-])(\d{1,2})(?::?(\d{2}))?/i);
  if (!match) {
    return 0;
  }
  const sign = match[1] === "-" ? -1 : 1;
  const hours = Number(match[2] || 0);
  const minutes = Number(match[3] || 0);
  return sign * ((hours * 60 + minutes) * 60 * 1000);
}

function buildDateInTimeZone(baseDate, timeZone, hour, minute, second, millisecond) {
  const parts = getTimeZoneDateParts(baseDate, timeZone);
  const utcGuess = new Date(
    Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      hour,
      minute,
      second,
      millisecond,
    ),
  );
  const offsetMs = getTimeZoneOffsetMillis(utcGuess, timeZone);
  return new Date(utcGuess.getTime() - offsetMs);
}

function getBirthdayDateKey(date, timeZone = kParisTimeZone) {
  const parts = getTimeZoneDateParts(date, timeZone);
  return `${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
}

function extractBirthdayDateKey(value) {
  if (!value) {
    return "";
  }

  const millis = timestampToMillis(value);
  if (millis !== null) {
    return getBirthdayDateKey(new Date(millis));
  }

  const raw = getTrimmedString(value);
  if (!raw) {
    return "";
  }

  let match = raw.match(/^(\d{4})-(\d{2})-(\d{2})(?:$|T)/);
  if (match) {
    return `${match[2]}-${match[3]}`;
  }

  match = raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (match) {
    return `${match[2]}-${match[1]}`;
  }

  match = raw.match(/^(\d{2})-(\d{2})-(\d{4})$/);
  if (match) {
    return `${match[2]}-${match[1]}`;
  }

  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    return getBirthdayDateKey(parsed);
  }

  return "";
}

function interpolateTemplate(template, replacements) {
  let output = getTrimmedString(template);
  Object.entries(replacements).forEach(([key, value]) => {
    output = output.replace(
      new RegExp(`\\{${key}\\}`, "g"),
      getTrimmedString(value),
    );
  });
  return output.replace(/\s{2,}/g, " ").trim();
}

function getBirthdayMessage(automationData = {}, userData = {}) {
  const messagesByStatus =
    automationData.messagesByStatus && typeof automationData.messagesByStatus === "object"
      ? automationData.messagesByStatus
      : {};
  const configured = messagesByStatus.default || {};
  const firstName = getTrimmedString(userData.first_name);

  return {
    title:
      interpolateTemplate(
        configured.title || kDefaultBirthdayMessage.title,
        {firstName},
      ) || kDefaultBirthdayMessage.title,
    body:
      interpolateTemplate(
        configured.body || kDefaultBirthdayMessage.body,
        {firstName},
      ) || kDefaultBirthdayMessage.body,
  };
}

async function resolveBirthdayEmail({admin, userId, userData = {}}) {
  const emailFromDoc = getTrimmedString(userData.email);
  if (emailFromDoc) {
    return emailFromDoc;
  }

  try {
    const authUser = await admin.auth().getUser(userId);
    return getTrimmedString(authUser.email);
  } catch (error) {
    console.log(
      `[birthday_runner] user=${userId} email=lookup_failed error=${error.message || error}`,
    );
    return "";
  }
}

function getBirthdaySendHour(automationData = {}) {
  const parsed = Number(automationData.sendHour);
  if (!Number.isFinite(parsed)) {
    return 9;
  }
  return Math.max(0, Math.min(23, Math.trunc(parsed)));
}

function getBirthdayRewardConfig(automationData = {}) {
  const reward =
    automationData.reward && typeof automationData.reward === "object"
      ? automationData.reward
      : null;
  const rewardType = getTrimmedString(reward && reward.type).toLowerCase();
  if (!reward) {
    return null;
  }
  if (
    rewardType !== "all_games_until_midnight" &&
    rewardType !== "free_play_all"
  ) {
    return null;
  }

  const value = Number(reward.value);
  const grantedBy = getTrimmedString(reward.grantedBy) || "birthday";
  return {
    type: "all_games_until_midnight",
    value: Number.isFinite(value) ? value : 1,
    grantedBy,
  };
}

async function grantBirthdayReward({
  firestore,
  admin,
  automationId,
  userId,
  birthdayDateKey,
  rewardConfig,
}) {
  if (!rewardConfig || rewardConfig.type !== "all_games_until_midnight") {
    return null;
  }

  const rewardEventId =
    `${automationId}__${userId}__${birthdayDateKey}`.replace(/[^A-Za-z0-9_-]/g, "_");
  const rewardEventRef = firestore.collection("reward_events").doc(rewardEventId);
  const existingRewardEvent = await rewardEventRef.get();

  if (existingRewardEvent.exists) {
    return {
      rewardEventId,
      alreadyExisted: true,
    };
  }

  await rewardEventRef.set({
    type: "all_games_until_midnight",
    status: "granted",
    uid: userId,
    value: rewardConfig.value || 1,
    grantedBy: rewardConfig.grantedBy || "birthday",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    rewardEventId,
    alreadyExisted: false,
  };
}

async function runBirthdayAutomation({
  firestore,
  admin,
  automationId = "birthday",
  dryRun = true,
  onlyUserIds = [],
  limit = 0,
  trigger = "manual_callable",
}) {
  const automation = await getActiveAutomationByIdAndType(
    firestore,
    automationId,
    kAutomationTypeBirthday,
  );
  if (!automation) {
    throw new Error(`birthday automation not found or inactive: ${automationId}`);
  }

  const normalizedOnlyUserIds = normalizeUserIds(onlyUserIds);
  const onlyUserIdsSet =
    normalizedOnlyUserIds.length > 0 ? new Set(normalizedOnlyUserIds) : null;
  const normalizedLimit = normalizeLimit(limit, 0, 500);
  const now = new Date();
  const todayKey = getBirthdayDateKey(now);
  const sendHour = getBirthdaySendHour(automation.data);
  const rewardConfig = getBirthdayRewardConfig(automation.data);
  const frequency = getTrimmedString(automation.data.frequency).toLowerCase() || "once";

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
      rewardType: rewardConfig ? rewardConfig.type : "",
      birthdayDateKey: todayKey,
    },
    matchedUsers: 0,
    birthdayUsersToday: 0,
    eligibleUsers: 0,
    queuedNotifications: 0,
    sentEmails: 0,
    rewardsGranted: 0,
    skippedAlreadySent: 0,
    skippedNoBirthday: 0,
    skippedNoToken: 0,
    skippedNoEmail: 0,
    skippedByOnlyUserIds: 0,
    pushFailures: 0,
    emailFailures: 0,
    errors: 0,
  };

  console.log(
    `[birthday_runner] start automation=${automation.id} trigger=${trigger} dryRun=${summary.dryRun} rewardType=${rewardConfig ? rewardConfig.type : "none"} birthdayDateKey=${todayKey}`,
  );

  try {
    const usersSnap = await firestore
      .collection("users")
      .where("user_role", "==", "joueur")
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

      console.log(
        `[birthday_runner] user=${userId} stage=loaded`,
      );

      if (onlyUserIdsSet && !onlyUserIdsSet.has(userId)) {
        summary.skippedByOnlyUserIds += 1;
        console.log(
          `[birthday_runner] user=${userId} skip=onlyUserIds`,
        );
        continue;
      }

      if (normalizedLimit > 0 && processedEligible >= normalizedLimit) {
        break;
      }

      const birthdayKey = extractBirthdayDateKey(userData.birthday);
      if (!birthdayKey) {
        summary.skippedNoBirthday += 1;
        console.log(
          `[birthday_runner] user=${userId} skip=no_birthday`,
        );
        continue;
      }
      if (birthdayKey !== todayKey) {
        console.log(
          `[birthday_runner] user=${userId} skip=not_today birthdayKey=${birthdayKey} todayKey=${todayKey}`,
        );
        continue;
      }

      summary.birthdayUsersToday += 1;

      const pushDeliveryState = await getDeliveryState(
        firestore,
        automation.id,
        userId,
        kNotificationChannelPush,
      );
      const emailDeliveryState = await getDeliveryState(
        firestore,
        automation.id,
        userId,
        kNotificationChannelEmail,
      );
      const pushAlreadyProcessedToday =
        getTrimmedString(pushDeliveryState.data.birthdayDateKey) === todayKey;
      const emailAlreadyProcessedToday =
        getTrimmedString(emailDeliveryState.data.birthdayDateKey) === todayKey;

      processedEligible += 1;
      summary.eligibleUsers += 1;

      if (!summary.dryRun) {
        let rewardMeta = {};
        let rewardGranted = false;
        if (rewardConfig) {
          const grantedReward = await grantBirthdayReward({
            firestore,
            admin,
            automationId: automation.id,
            userId,
            birthdayDateKey: todayKey,
            rewardConfig,
          });
          if (grantedReward) {
            rewardGranted = true;
            if (grantedReward.alreadyExisted !== true) {
              summary.rewardsGranted += 1;
            }
            rewardMeta = {
              rewardType: rewardConfig.type,
              rewardEventId: grantedReward.rewardEventId,
            };
            console.log(
              `[birthday_runner] user=${userId} reward=${grantedReward.alreadyExisted === true ? "already_exists" : "granted"} rewardEventId=${grantedReward.rewardEventId}`,
            );
          }
        } else {
          console.log(
            `[birthday_runner] user=${userId} reward=skipped reason=no_reward_config`,
          );
        }

        let notificationDocId = "";
        let notificationQueued = false;
        let pushStatus = pushAlreadyProcessedToday ? "skipped_already_processed" : "skipped";
        let emailStatus = emailAlreadyProcessedToday ? "skipped_already_processed" : "skipped";
        const message = getBirthdayMessage(automation.data, userData);

        if (pushAlreadyProcessedToday) {
          summary.skippedAlreadySent += 1;
          console.log(
            `[birthday_runner] user=${userId} push=skipped reason=already_processed rewardGranted=${rewardGranted}`,
          );
        } else {
          try {
            const tokensSnap = await firestore
              .collection("users")
              .doc(userId)
              .collection(kFcmTokensCollection)
              .limit(1)
              .get();

            if (tokensSnap.empty) {
              pushStatus = "skipped_no_token";
              summary.skippedNoToken += 1;
              console.log(
                `[birthday_runner] user=${userId} push=skipped reason=no_token rewardGranted=${rewardGranted}`,
              );
            } else {
              notificationDocId = `${automation.id}_${userId}_${todayKey.replace("-", "")}`;
              notificationQueued = await enqueueUserPushNotification({
                firestore,
                admin,
                docId: notificationDocId,
                title: message.title,
                body: message.body,
                userId,
                createdBy: `system/notification_automation/${automation.id}`,
              });

              if (notificationQueued) {
                pushStatus = "queued";
                summary.queuedNotifications += 1;
                console.log(
                  `[birthday_runner] user=${userId} push=queued docId=${notificationDocId} rewardGranted=${rewardGranted}`,
                );
              } else {
                pushStatus = "skipped_existing_doc";
                summary.skippedAlreadySent += 1;
                console.log(
                  `[birthday_runner] user=${userId} push=skipped reason=existing_doc docId=${notificationDocId} rewardGranted=${rewardGranted}`,
                );
              }
            }
          } catch (error) {
            pushStatus = "failed";
            summary.pushFailures += 1;
            console.log(
              `[birthday_runner] user=${userId} push=failed error=${error.message || error} rewardGranted=${rewardGranted}`,
            );
          }
        }

        if (emailAlreadyProcessedToday) {
          summary.skippedAlreadySent += 1;
          console.log(
            `[birthday_runner] user=${userId} email=skipped reason=already_processed rewardGranted=${rewardGranted}`,
          );
        } else {
          try {
            const email = await resolveBirthdayEmail({admin, userId, userData});
            if (!email) {
              emailStatus = "skipped_no_email";
              summary.skippedNoEmail += 1;
              console.log(
                `[birthday_runner] user=${userId} email=skipped reason=no_email rewardGranted=${rewardGranted}`,
              );
            } else {
              await sendTextEmail({
                to: email,
                subject: message.title,
                text: message.body,
              });
              emailStatus = "sent";
              summary.sentEmails += 1;
              console.log(
                `[birthday_runner] user=${userId} email=queued to=${email} rewardGranted=${rewardGranted}`,
              );
            }
          } catch (error) {
            emailStatus = "failed";
            summary.emailFailures += 1;
            console.log(
              `[birthday_runner] user=${userId} email=failed error=${error.message || error} rewardGranted=${rewardGranted}`,
            );
          }
        }

        if (pushStatus !== "failed") {
          await markDeliveryStateSent({
            admin,
            firestore,
            automationId: automation.id,
            userId,
            runId,
            notificationDocId,
            channel: kNotificationChannelPush,
            status: pushStatus,
            exists: pushDeliveryState.exists,
            extra: {
              birthdayDateKey: todayKey,
              notificationQueued,
              ...rewardMeta,
            },
          });
        }
        if (emailStatus !== "failed") {
          await markDeliveryStateSent({
            admin,
            firestore,
            automationId: automation.id,
            userId,
            runId,
            notificationDocId: "",
            channel: kNotificationChannelEmail,
            status: emailStatus,
            exists: emailDeliveryState.exists,
            extra: {
              birthdayDateKey: todayKey,
              ...rewardMeta,
            },
          });
        }
        console.log(
          `[birthday_runner] user=${userId} delivery_state=updated rewardGranted=${rewardGranted} pushStatus=${pushStatus} emailStatus=${emailStatus}`,
        );
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
  getBirthdaySendHour,
  runBirthdayAutomation,
};
