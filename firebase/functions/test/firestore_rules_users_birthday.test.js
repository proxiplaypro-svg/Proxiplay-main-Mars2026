#!/usr/bin/env node

// Date de naissance verrouillee (1.1.4) : le joueur la saisit une fois, ne
// peut plus la modifier ni la retirer, ne peut plus supprimer son document
// pour le recreer avec une autre date, et les anciennes versions de l'app
// (qui renvoient la date enregistree a chaque validation du formulaire)
// continuent de fonctionner. La correction passe par la callable
// adminCorrectPlayerBirthday, jamais par une ecriture client, meme admin.
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_users_birthday.test.js"
//
// FIRESTORE_RULES_FILE permet de rejouer ces assertions contre une copie des
// regles deployees (elles doivent alors echouer sur les failles corrigees).

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {Timestamp, deleteField, doc, setDoc, updateDoc, deleteDoc, getDoc} =
  require("firebase/firestore");

const [emulatorHost, emulatorPort] = (process.env.FIRESTORE_EMULATOR_HOST || "").split(":");
if (!emulatorHost || !/^\d+$/.test(emulatorPort || "")) {
  throw new Error("FIRESTORE_EMULATOR_HOST requis (hôte:port) : aucun accès production n'est autorisé.");
}

let testEnv;
const kBirthday = Timestamp.fromDate(new Date("1990-05-17T22:00:00Z"));
const kOtherBirthday = Timestamp.fromDate(new Date("1985-01-02T23:00:00Z"));
const kAdminToken = {admin: true};

function profileFields() {
  return {
    first_name: "Alice",
    last_name: "Martin",
    display_name: "Alice Martin",
    phone_number: "0600000000",
    city: "Lille",
    profile_completed: true,
    profile_completed_at: Timestamp.now(),
    profile_schema_version: 1,
  };
}

async function seedUser(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), data);
  });
}

function playerDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function adminDb() {
  return testEnv.authenticatedContext("admin_uid", kAdminToken).firestore();
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-rules-birthday",
    firestore: {
      rules: fs.readFileSync(
        process.env.FIRESTORE_RULES_FILE ||
          path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
      host: emulatorHost,
      port: Number(emulatorPort),
    },
  });
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedUser("with_birthday", {uid: "with_birthday", user_role: "joueur", birthday: kBirthday});
  await seedUser("without_birthday", {uid: "without_birthday", user_role: "joueur"});
  await seedUser("null_birthday", {uid: "null_birthday", user_role: "joueur", birthday: null});
  await seedUser("admin_uid", {uid: "admin_uid", user_role: "admin"});
});

test.after(async () => {
  await testEnv?.cleanup();
});

test("un joueur sans date la saisit une premiere fois avec son profil", async () => {
  await assertSucceeds(setDoc(doc(playerDb("without_birthday"), "users", "without_birthday"),
    {...profileFields(), birthday: kBirthday}, {merge: true}));
});

test("une date enregistree a null compte comme non saisie", async () => {
  await assertSucceeds(updateDoc(doc(playerDb("null_birthday"), "users", "null_birthday"),
    {birthday: kBirthday}));
});

test("ancienne version de l'app : renvoyer la meme date avec le profil reste autorise", async () => {
  await assertSucceeds(setDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {...profileFields(), birthday: kBirthday}, {merge: true}));
});

test("une date enregistree ne peut plus etre modifiee par le joueur", async () => {
  await assertFails(setDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {...profileFields(), birthday: kOtherBirthday}, {merge: true}));
  await assertFails(updateDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {birthday: kOtherBirthday}));
});

test("une date enregistree ne peut etre ni retiree ni remise a null", async () => {
  await assertFails(updateDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {birthday: deleteField()}));
  await assertFails(updateDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {birthday: null}));
});

test("la premiere saisie doit etre une date plausible", async () => {
  const db = playerDb("without_birthday");
  const ref = doc(db, "users", "without_birthday");
  await assertFails(updateDoc(ref, {birthday: Timestamp.fromMillis(Date.now() + 86400000)}));
  await assertFails(updateDoc(ref, {birthday: Timestamp.fromDate(new Date("1899-12-31T00:00:00Z"))}));
  await assertFails(updateDoc(ref, {birthday: "1990-05-18"}));
  await assertFails(updateDoc(ref, {birthday: 642981600000}));
});

test("le profil sans date reste modifiable (nom, ville) sans toucher a la date", async () => {
  await assertSucceeds(updateDoc(doc(playerDb("with_birthday"), "users", "with_birthday"),
    {city: "Roubaix", first_name: "Alicia"}));
});

test("creation du profil : date plausible acceptee, date invalide refusee", async () => {
  await assertSucceeds(setDoc(doc(playerDb("new_player"), "users", "new_player"),
    {uid: "new_player", user_role: "joueur", birthday: kBirthday}));
  await assertFails(setDoc(doc(playerDb("bad_type"), "users", "bad_type"),
    {uid: "bad_type", user_role: "joueur", birthday: "1990-05-18"}));
  await assertFails(setDoc(doc(playerDb("future"), "users", "future"),
    {uid: "future", user_role: "joueur", birthday: Timestamp.fromMillis(Date.now() + 86400000)}));
});

test("suppression puis recreation : le joueur ne peut pas supprimer son document", async () => {
  const db = playerDb("with_birthday");
  const ref = doc(db, "users", "with_birthday");
  await assertFails(deleteDoc(ref));
  // Le document existe toujours : une "recreation" par set() complet est une
  // mise a jour, refusee des qu'elle change la date.
  await assertFails(setDoc(ref, {uid: "with_birthday", user_role: "joueur", birthday: kOtherBirthday}));
  await assertFails(setDoc(ref, {uid: "with_birthday", user_role: "joueur", birthday: kOtherBirthday},
    {merge: true}));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const snap = await getDoc(doc(context.firestore(), "users", "with_birthday"));
    if (!snap.data().birthday.isEqual(kBirthday)) throw new Error("date modifiee");
  });
});

test("un administrateur ne modifie pas la date depuis un client, mais gere le reste", async () => {
  const db = adminDb();
  await assertFails(updateDoc(doc(db, "users", "with_birthday"), {birthday: kOtherBirthday}));
  await assertFails(updateDoc(doc(db, "users", "without_birthday"), {birthday: kBirthday}));
  await assertSucceeds(updateDoc(doc(db, "users", "with_birthday"),
    {city: "Lens", account_status: "approved"}));
  await assertSucceeds(deleteDoc(doc(db, "users", "with_birthday")));
});

test("journal des corrections : lecture admin seulement, aucune ecriture client", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/with_birthday/birthday_corrections/c1"),
      {reason: "erreur de saisie", previous_age_band: "18_plus", new_age_band: "18_plus"});
  });
  const player = playerDb("with_birthday");
  await assertFails(getDoc(doc(player, "users/with_birthday/birthday_corrections/c1")));
  await assertFails(setDoc(doc(player, "users/with_birthday/birthday_corrections/c2"), {reason: "x"}));
  const admin = adminDb();
  await assertSucceeds(getDoc(doc(admin, "users/with_birthday/birthday_corrections/c1")));
  await assertFails(setDoc(doc(admin, "users/with_birthday/birthday_corrections/c2"), {reason: "x"}));
  await assertFails(deleteDoc(doc(admin, "users/with_birthday/birthday_corrections/c1")));
});
