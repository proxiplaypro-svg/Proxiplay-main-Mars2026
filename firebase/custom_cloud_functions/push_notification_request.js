const admin = require("firebase-admin");

function toUserRefPath(userRefOrPath) {
  if (!userRefOrPath) {
    return "";
  }
  if (typeof userRefOrPath === "string") {
    return userRefOrPath.trim();
  }
  if (typeof userRefOrPath.path === "string") {
    return userRefOrPath.path;
  }
  return "";
}

async function queuePushNotificationRequest(db, {
  title,
  body,
  userRefOrPath,
  createdBy,
  initialPageName = "",
  parameterData = "",
  targetAudience = "All",
  targetUserGroup = "All",
}) {
  const userRefPath = toUserRefPath(userRefOrPath);
  if (!userRefPath) {
    throw new Error("Missing target user ref path for push notification request.");
  }

  await db.collection("ff_push_notifications").add({
    notification_title: title || "",
    notification_text: body || "",
    notification_image_url: "",
    notification_sound: "",
    parameter_data: parameterData,
    initial_page_name: initialPageName,
    target_audience: targetAudience,
    target_user_group: targetUserGroup,
    user_refs: userRefPath,
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy || "system/custom_cloud_function",
  });
}

module.exports = {
  queuePushNotificationRequest,
};
