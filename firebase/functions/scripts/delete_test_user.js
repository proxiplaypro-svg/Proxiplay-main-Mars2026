#!/usr/bin/env node

const admin = require("firebase-admin");

const email = process.argv[2];
const projectId =
  process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "proxi-play-odzp2e";

if (!email) {
  console.error("Usage: node scripts/delete_test_user.js <email>");
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
}

async function main() {
  const authUser = await admin.auth().getUserByEmail(email);
  const uid = authUser.uid;

  console.log(`Found Auth user ${email} uid=${uid}`);

  const userRef = admin.firestore().collection("users").doc(uid);
  const userSnap = await userRef.get();
  console.log(`Firestore doc exists=${userSnap.exists} path=users/${uid}`);

  if (userSnap.exists) {
    await userRef.delete();
    console.log(`Deleted Firestore doc users/${uid}`);
  }

  await admin.auth().deleteUser(uid);
  console.log(`Deleted Auth user uid=${uid}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("delete_test_user failed", error);
    process.exit(1);
  });
