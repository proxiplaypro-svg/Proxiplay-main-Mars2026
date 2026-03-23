const {
  kAutomationTypeBirthday,
  kDefaultBirthdayMessage,
  kAutomationTypeInactivePlayer,
  kDefaultInactivePlayerMessagesByStatus,
  kInactivePlayerStatuses,
  kNotificationChannelPush,
} = require("../constants");

const kDefaultAutomations = [
  {
    id: "birthday",
    data: {
      name: "Anniversaire",
      type: kAutomationTypeBirthday,
      isActive: true,
      channel: kNotificationChannelPush,
      frequency: "once",
      sendHour: 9,
      filters: {
        remainingPartsOnly: false,
      },
      messagesByStatus: {
        default: kDefaultBirthdayMessage,
      },
      reward: {
        type: "all_games_until_midnight",
        value: 1,
        grantedBy: "birthday",
      },
    },
  },
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
