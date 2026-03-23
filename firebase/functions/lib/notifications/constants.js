const kNotificationAutomationsCollection = "notification_automations";
const kNotificationDeliveryStateCollection = "notification_delivery_state";
const kRunsSubcollection = "runs";
const kFcmTokensCollection = "fcm_tokens";
const kPushNotificationsCollection = "ff_push_notifications";
const kAutomationTypeInactivePlayer = "inactive_player";
const kAutomationTypeBirthday = "birthday";
const kNotificationChannelPush = "push";
const kNotificationChannelEmail = "email";
const kInactivePlayerStatuses = ["a_relancer", "dormant", "mort_probable"];
const kParisTimeZone = "Europe/Paris";

const kDefaultInactivePlayerMessagesByStatus = {
  mort_probable: {
    title: "Nous vous manquons ?",
    body: "Revenez jouer à ProxiPlay et tentez de remporter des superbes lots !",
  },
  dormant: {
    title: "Ça fait longtemps !",
    body: "Retrouvez les jeux ProxiPlay et vos lots récompenses. Nouveau jeu disponible !",
  },
  a_relancer: {
    title: "Revenez jouer !",
    body: "Continuez à jouer pour accumuler vos prochaines victoires !",
  },
  default: {
    title: "Revenez jouer !",
    body: "Nous vous avons beaucoup manqué !",
  },
};

const kDefaultBirthdayMessage = {
  title: "Joyeux anniversaire !",
  body: "Profitez de vos avantages du jour et tentez votre chance !",
};

module.exports = {
  kAutomationTypeBirthday,
  kAutomationTypeInactivePlayer,
  kDefaultBirthdayMessage,
  kDefaultInactivePlayerMessagesByStatus,
  kFcmTokensCollection,
  kInactivePlayerStatuses,
  kNotificationAutomationsCollection,
  kNotificationChannelEmail,
  kNotificationChannelPush,
  kParisTimeZone,
  kNotificationDeliveryStateCollection,
  kPushNotificationsCollection,
  kRunsSubcollection,
};
