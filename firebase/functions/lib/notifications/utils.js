const {
  kDefaultInactivePlayerMessagesByStatus,
  kInactivePlayerStatuses,
} = require("./constants");

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function toBoolean(value, defaultValue = false) {
  if (typeof value === "boolean") {
    return value;
  }
  const parsed = getTrimmedString(value).toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(parsed)) {
    return true;
  }
  if (["0", "false", "no", "n", "off"].includes(parsed)) {
    return false;
  }
  return defaultValue;
}

function timestampToMillis(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function normalizeUserIds(values) {
  if (!Array.isArray(values)) {
    return [];
  }
  return Array.from(
    new Set(
      values
        .map((value) => getTrimmedString(value))
        .filter((value) => value.length > 0),
    ),
  );
}

function normalizeLimit(value, defaultValue = 0, maxValue = 500) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return defaultValue;
  }
  return Math.min(maxValue, Math.trunc(parsed));
}

function getInactivePlayerMessage(status, automationData = {}) {
  const configuredMessages =
    automationData.messagesByStatus &&
    typeof automationData.messagesByStatus === "object"
      ? automationData.messagesByStatus
      : {};
  const defaultMessages = kDefaultInactivePlayerMessagesByStatus;
  const configured =
    configuredMessages[status] ||
    configuredMessages.default ||
    defaultMessages[status] ||
    defaultMessages.default;

  return {
    title: getTrimmedString(configured && configured.title) || defaultMessages.default.title,
    body: getTrimmedString(configured && configured.body) || defaultMessages.default.body,
  };
}

function getInactiveStatusesFromAutomation(automationData = {}) {
  const statuses = Array.isArray(automationData.targetStatuses)
    ? automationData.targetStatuses
    : Array.isArray(automationData.statuses)
      ? automationData.statuses
      : kInactivePlayerStatuses;

  return Array.from(
    new Set(
      statuses
        .map((status) => getTrimmedString(status))
        .filter((status) => status.length > 0),
    ),
  );
}

function getInactivePlayerFrequency(automationData = {}) {
  const frequency = getTrimmedString(automationData.frequency).toLowerCase();
  return frequency === "repeat" ? "repeat" : "once";
}

function getInactivePlayerSendHour(automationData = {}) {
  const parsed = Number(automationData.sendHour);
  if (!Number.isFinite(parsed)) {
    return 18;
  }
  return Math.max(0, Math.min(23, Math.trunc(parsed)));
}

function getInactivePlayerRemainingPartsOnly(automationData = {}) {
  const filters =
    automationData.filters && typeof automationData.filters === "object"
      ? automationData.filters
      : {};
  return toBoolean(filters.remainingPartsOnly, false);
}

module.exports = {
  getInactivePlayerFrequency,
  getInactivePlayerMessage,
  getInactivePlayerRemainingPartsOnly,
  getInactivePlayerSendHour,
  getInactiveStatusesFromAutomation,
  getTrimmedString,
  normalizeLimit,
  normalizeUserIds,
  timestampToMillis,
  toBoolean,
};
