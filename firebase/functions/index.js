const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const kFcmTokensCollection = "fcm_tokens";
const kPushNotificationsCollection = "ff_push_notifications";
const firestore = admin.firestore();

const kPushNotificationRuntimeOpts = {
  timeoutSeconds: 540,
  memory: "2GB",
};

exports.addFcmToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    return "Failed: Unauthenticated calls are not allowed.";
  }
  const userDocPath = data.userDocPath;
  const fcmToken = data.fcmToken;
  const deviceType = data.deviceType;
  if (
    typeof userDocPath === "undefined" ||
    typeof fcmToken === "undefined" ||
    typeof deviceType === "undefined" ||
    userDocPath.split("/").length <= 1 ||
    fcmToken.length === 0 ||
    deviceType.length === 0
  ) {
    return "Invalid arguments encoutered when adding FCM token.";
  }
  if (context.auth.uid != userDocPath.split("/")[1]) {
    return "Failed: Authenticated user doesn't match user provided.";
  }
  const existingTokens = await firestore
    .collectionGroup(kFcmTokensCollection)
    .where("fcm_token", "==", fcmToken)
    .get();
  var userAlreadyHasToken = false;
  for (var doc of existingTokens.docs) {
    const user = doc.ref.parent.parent;
    if (user.path != userDocPath) {
      // Should never have the same FCM token associated with multiple users.
      await doc.ref.delete();
    } else {
      userAlreadyHasToken = true;
    }
  }
  if (userAlreadyHasToken) {
    return "FCM token already exists for this user. Ignoring...";
  }

  // Best-effort: denormalize user role onto the token doc so we can target
  // notifications by role without expensive joins later.
  let userRole = "";
  try {
    const userSnap = await firestore.doc(userDocPath).get();
    userRole = (userSnap.exists && userSnap.data().user_role) || "";
  } catch (e) {
    console.log(`Warning: unable to read user role for ${userDocPath}: ${e}`);
  }

  await getUserFcmTokensCollection(userDocPath).doc().set({
    fcm_token: fcmToken,
    device_type: deviceType,
    user_role: userRole,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  return "Successfully added FCM token!";
});

async function assertIsAdmin(uid) {
  const userSnap = await firestore.doc(`users/${uid}`).get();
  const role = (userSnap.exists && userSnap.data().user_role) || "";
  if (role !== "admin") {
    throw new Error("permission-denied: admin required");
  }
}

/**
 * Create a push notification request (stored in ff_push_notifications) that will be sent
 * by sendPushNotificationsTrigger (immediate) or by the scheduled processor (scheduled/repeat).
 *
 * Inputs:
 *  - title, body (required)
 *  - imageUrl (optional)
 *  - targetDevice: "All" | "Android" | "iOS" (optional, default "All")
 *  - targetUserGroup: "All" | "Admins" | "NormalUsers" (optional, default "All")
 *  - userRefs (optional): array of "users/<uid>" to target specific users
 *  - scheduledTimeMs (optional): unix ms for scheduled send
 *  - repeatEveryMinutes (optional): integer minutes
 *  - repeatCount (optional): integer, 0/undefined means infinite
 */
exports.createAdminPushNotification = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);

    const title = (data.title || "").toString().trim();
    const body = (data.body || "").toString().trim();
    const imageUrl = (data.imageUrl || "").toString().trim();
    const targetDevice = (data.targetDevice || "All").toString();
    const targetUserGroup = (data.targetUserGroup || "All").toString();
    const userRefs = Array.isArray(data.userRefs)
      ? data.userRefs.map((s) => (s || "").toString().trim()).filter((s) => s)
      : [];
    const scheduledTimeMs = data.scheduledTimeMs;
    const repeatEveryMinutes = data.repeatEveryMinutes;
    const repeatCount = data.repeatCount;

    if (!title || !body) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "title and body are required",
      );
    }

    const doc = {
      notification_title: title,
      notification_text: body,
      notification_image_url: imageUrl,
      notification_sound: "",
      parameter_data: "",
      initial_page_name: "",
      target_audience: targetDevice, // existing field (device_type)
      target_user_group: targetUserGroup, // new field (role targeting)
      user_refs: userRefs.length ? userRefs.join(",") : "",
      status: "started",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      created_by: `users/${context.auth.uid}`,
      ...(Number.isFinite(repeatEveryMinutes)
        ? { repeat_every_minutes: Number(repeatEveryMinutes) }
        : {}),
      ...(Number.isFinite(repeatCount) ? { repeat_count: Number(repeatCount) } : {}),
    };

    if (Number.isFinite(scheduledTimeMs) && Number(scheduledTimeMs) > 0) {
      doc.scheduled_time = admin.firestore.Timestamp.fromMillis(
        Number(scheduledTimeMs),
      );
      doc.status = "scheduled";
    }

    const ref = await firestore.collection(kPushNotificationsCollection).add(doc);
    return { ok: true, id: ref.id };
  },
);

exports.sendPushNotificationsTrigger = functions
  .runWith(kPushNotificationRuntimeOpts)
  .firestore.document(`${kPushNotificationsCollection}/{id}`)
  .onCreate(async (snapshot, _) => {
    try {
      // Ignore scheduled push notifications on create
      const scheduledTime = snapshot.data().scheduled_time || "";
      if (scheduledTime) {
        return;
      }

      await sendPushNotifications(snapshot);
    } catch (e) {
      console.log(`Error: ${e}`);
      await snapshot.ref.update({ status: "failed", error: `${e}` });
    }
  });

async function sendPushNotifications(snapshot) {
  const notificationData = snapshot.data();
  const title = notificationData.notification_title || "";
  const body = notificationData.notification_text || "";
  const imageUrl = notificationData.notification_image_url || "";
  const sound = notificationData.notification_sound || "";
  const parameterData = notificationData.parameter_data || "";
  const targetAudience = notificationData.target_audience || "";
  const targetUserGroup = notificationData.target_user_group || "All";
  const initialPageName = notificationData.initial_page_name || "";
  const userRefsStr = notificationData.user_refs || "";
  const batchIndex = notificationData.batch_index || 0;
  const numBatches = notificationData.num_batches || 0;
  const status = notificationData.status || "";

  if (status !== "" && status !== "started") {
    console.log(`Already processed ${snapshot.ref.path}. Skipping...`);
    return;
  }

  if (title === "" || body === "") {
    await snapshot.ref.update({ status: "failed" });
    return;
  }

  const userRefs = userRefsStr === "" ? [] : userRefsStr.trim().split(",");
  var tokens = new Set();
  if (userRefsStr) {
    for (var userRef of userRefs) {
      const userTokens = await firestore
        .doc(userRef)
        .collection(kFcmTokensCollection)
        .get();
      userTokens.docs.forEach((token) => {
        const data = token.data();
        if (typeof data.fcm_token === "undefined" || !data.fcm_token) return;
        tokens.add(data.fcm_token);
      });
    }
  } else {
    var userTokensQuery = firestore.collectionGroup(kFcmTokensCollection);
    // Handle batched push notifications by splitting tokens up by document
    // id.
    if (numBatches > 0) {
      userTokensQuery = userTokensQuery
        .orderBy(admin.firestore.FieldPath.documentId())
        .startAt(getDocIdBound(batchIndex, numBatches))
        .endBefore(getDocIdBound(batchIndex + 1, numBatches));
    }
    const userTokens = await userTokensQuery.get();
    // Filter by device audience + (optionally) by user role group.
    await Promise.all(
      userTokens.docs.map(async (tokenDoc) => {
        const data = tokenDoc.data();
        const audienceMatches =
          targetAudience === "All" || data.device_type === targetAudience;
        if (!audienceMatches || typeof data.fcm_token === "undefined") return;

        if (!targetUserGroup || targetUserGroup === "All") {
          tokens.add(data.fcm_token);
          return;
        }

        let role = data.user_role || "";
        if (!role) {
          // Backward compatibility: older token docs may not have user_role.
          try {
            const userRef = tokenDoc.ref.parent.parent;
            const userSnap = await userRef.get();
            role = (userSnap.exists && userSnap.data().user_role) || "";
          } catch (_) {
            role = "";
          }
        }

        const isAdmin = role === "admin";
        const roleMatches =
          targetUserGroup === "Admins"
            ? isAdmin
            : targetUserGroup === "NormalUsers"
              ? !isAdmin
              : true;
        if (roleMatches) tokens.add(data.fcm_token);
      }),
    );
  }

  const tokensArr = Array.from(tokens);
  console.log(
    `Preparing push notification ${snapshot.id}: tokens=${tokensArr.length}, ` +
      `audience=${targetAudience}, group=${targetUserGroup}, ` +
      `userRefs=${userRefsStr ? userRefs.length : 0}`,
  );
  if (tokensArr.length === 0) {
    await snapshot.ref.update({
      status: "failed",
      error: "no_tokens",
      num_sent: 0,
    });
    return;
  }
  var messageBatches = [];
  for (let i = 0; i < tokensArr.length; i += 500) {
    const tokensBatch = tokensArr.slice(i, Math.min(i + 500, tokensArr.length));
    const messages = {
      notification: {
        title,
        body,
        ...(imageUrl && { imageUrl: imageUrl }),
      },
      data: {
        initialPageName,
        parameterData,
      },
      android: {
        notification: {
          ...(sound && { sound: sound }),
        },
      },
      apns: {
        payload: {
          aps: {
            ...(sound && { sound: sound }),
          },
        },
      },
      tokens: tokensBatch,
    };
    messageBatches.push(messages);
  }

  var numSent = 0;
  await Promise.all(
    messageBatches.map(async (messages) => {
      const response = await admin.messaging().sendEachForMulticast(messages);
      numSent += response.successCount;
      if (response.failureCount > 0) {
        const errorCodes = response.responses
          .filter((r) => !r.success)
          .map((r) => r.error && r.error.code)
          .filter((code) => !!code);
        if (errorCodes.length) {
          console.log(
            `Push send errors for ${snapshot.id}: ${errorCodes
              .slice(0, 10)
              .join(", ")}`,
          );
        }
      }
    }),
  );

  await snapshot.ref.update({ status: "succeeded", num_sent: numSent });
}

/**
 * Scheduled processing for push notifications:
 * - finds documents in ff_push_notifications with scheduled_time <= now and status == "scheduled"
 * - sends them, then marks succeeded, or reschedules if repeat_every_minutes is set.
 *
 * NOTE: Requires deployment. Runs every minute.
 */
exports.processScheduledPushNotifications = functions
  .runWith(kPushNotificationRuntimeOpts)
  .pubsub.schedule("every 1 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await firestore
      .collection(kPushNotificationsCollection)
      .where("status", "==", "scheduled")
      .where("scheduled_time", "<=", now)
      .limit(20)
      .get();

    await Promise.all(
      snap.docs.map(async (doc) => {
        try {
          await sendPushNotifications(doc);
          const data = doc.data();
          const repeatEvery = Number(data.repeat_every_minutes || 0);
          let repeatCount = Number(data.repeat_count || 0);
          if (repeatEvery > 0) {
            // 0/undefined = infinite repeats
            if (repeatCount > 0) {
              repeatCount -= 1;
            }
            if (repeatCount === 0 && Number(data.repeat_count || 0) > 0) {
              // finished
              return;
            }
            const nextTime = admin.firestore.Timestamp.fromMillis(
              Date.now() + repeatEvery * 60 * 1000,
            );
            await doc.ref.update({
              status: "scheduled",
              scheduled_time: nextTime,
              ...(Number(data.repeat_count || 0) > 0 ? { repeat_count: repeatCount } : {}),
            });
          }
        } catch (e) {
          console.log(`Error processing scheduled notification ${doc.id}: ${e}`);
          await doc.ref.update({ status: "failed", error: `${e}` });
        }
      }),
    );
  });

function getUserFcmTokensCollection(userDocPath) {
  return firestore.doc(userDocPath).collection(kFcmTokensCollection);
}

function getDocIdBound(index, numBatches) {
  if (index <= 0) {
    return "users/(";
  }
  if (index >= numBatches) {
    return "users/}";
  }
  const numUidChars = 62;
  const twoCharOptions = Math.pow(numUidChars, 2);

  var twoCharIdx = (index * twoCharOptions) / numBatches;
  var firstCharIdx = Math.floor(twoCharIdx / numUidChars);
  var secondCharIdx = Math.floor(twoCharIdx % numUidChars);
  const firstChar = getCharForIndex(firstCharIdx);
  const secondChar = getCharForIndex(secondCharIdx);
  return "users/" + firstChar + secondChar;
}

function getCharForIndex(charIdx) {
  if (charIdx < 10) {
    return String.fromCharCode(charIdx + "0".charCodeAt(0));
  } else if (charIdx < 36) {
    return String.fromCharCode("A".charCodeAt(0) + charIdx - 10);
  } else {
    return String.fromCharCode("a".charCodeAt(0) + charIdx - 36);
  }
}
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
  let firestore = admin.firestore();
  let userRef = firestore.doc("users/" + user.uid);
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("enseigne_game")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(
                `Deleting document ${d.id} from collection enseigne_game`,
              );
              await d.ref.delete();
            }
          });
      }
    });
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("horaires")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(`Deleting document ${d.id} from collection horaires`);
              await d.ref.delete();
            }
          });
      }
    });
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("images")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(`Deleting document ${d.id} from collection images`);
              await d.ref.delete();
            }
          });
      }
    });
  await firestore.collection("users").doc(user.uid).delete();
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        console.log(`Deleting document ${doc.id} from collection enseignes`);
        await doc.ref.delete();
      }
    });
  await firestore
    .collection("games")
    .where("create_by", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        console.log(`Deleting document ${doc.id} from collection games`);
        await doc.ref.delete();
      }
    });
});
