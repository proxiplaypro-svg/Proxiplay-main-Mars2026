const admin = require("firebase-admin");

admin.initializeApp({
  projectId: "proxi-play-odzp2",
});

async function main() {
  const uid = "CKRlbsC8x2cUUsUPFy4rG67CyJHG";

  await admin.auth().setCustomUserClaims(uid, { admin: true });

  const user = await admin.auth().getUser(uid);
  console.log("Custom claims:", user.customClaims);
}

main()
  .then(() => {
    console.log("Done");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });