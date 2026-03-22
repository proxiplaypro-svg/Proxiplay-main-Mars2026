const {kPushNotificationsCollection} = require("./constants");

async function enqueueUserPushNotification({
  firestore,
  admin,
  docId,
  title,
  body,
  userId,
  createdBy,
  initialPageName = "",
  parameterData = "",
}) {
  const ref = firestore.collection(kPushNotificationsCollection).doc(docId);
  const existing = await ref.get();
  if (existing.exists) {
    return false;
  }

  await ref.set({
    notification_title: title,
    notification_text: body,
    notification_image_url: "",
    notification_sound: "",
    parameter_data: parameterData,
    initial_page_name: initialPageName,
    target_audience: "All",
    target_user_group: "All",
    user_refs: `users/${userId}`,
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy,
  });

  return true;
}

module.exports = {
  enqueueUserPushNotification,
};
