const {
  kAutomationTypeInactivePlayer,
  kDefaultInactivePlayerMessagesByStatus,
  kInactivePlayerStatuses,
  kNotificationChannelPush,
} = require("../constants");

const kDefaultAutomations = [
  {
    id: "inactive_players_7d",
    data: {
      name: "Inactive players 7d",
      type: kAutomationTypeInactivePlayer,
      isActive: true,
      channel: kNotificationChannelPush,
      cooldownDays: 7,
      frequency: "once",
      sendHour: 18,
      filters: {
        remainingPartsOnly: false,
      },
      targetStatuses: kInactivePlayerStatuses,
      messagesByStatus: kDefaultInactivePlayerMessagesByStatus,
    },
  },
];

module.exports = {
  kDefaultAutomations,
};
