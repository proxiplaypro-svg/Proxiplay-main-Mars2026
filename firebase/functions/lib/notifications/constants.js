const kNotificationAutomationsCollection = "notification_automations";
const kNotificationDeliveryStateCollection = "notification_delivery_state";
const kRunsSubcollection = "runs";
const kFcmTokensCollection = "fcm_tokens";
const kPushNotificationsCollection = "ff_push_notifications";
const kAutomationTypeInactivePlayer = "inactive_player";
const kNotificationChannelPush = "push";
const kInactivePlayerStatuses = ["a_relancer", "dormant", "mort_probable"];

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

module.exports = {
  kAutomationTypeInactivePlayer,
  kDefaultInactivePlayerMessagesByStatus,
  kFcmTokensCollection,
  kInactivePlayerStatuses,
  kNotificationAutomationsCollection,
  kNotificationChannelPush,
  kNotificationDeliveryStateCollection,
  kPushNotificationsCollection,
  kRunsSubcollection,
};
