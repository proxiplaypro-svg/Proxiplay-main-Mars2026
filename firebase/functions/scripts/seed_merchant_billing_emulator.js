// Donnees de test de l'espace commercant, EMULATEURS UNIQUEMENT.
//
//   firebase emulators:start --only auth,firestore,functions --project demo-proxiplay-stripe
//   node scripts/seed_merchant_billing_emulator.js
//   -> http://localhost:5500/espace-commercant/?emulator=1
//
// Comptes de test (emulateur Auth, projet demo- isole, jamais en production) :
//   commercant : merchant.test@proxiplay.test / Test-Merchant-2026!
//   joueur     : player.test@proxiplay.test   / Test-Player-2026!
// Refuse de s'executer hors emulateur ou hors projet demo-.

const kProjectId = process.env.GCLOUD_PROJECT || "demo-proxiplay-stripe";
const kAuthHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const kFirestoreHost = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
if (!kProjectId.startsWith("demo-")) throw new Error("Projet demo- requis (emulateurs uniquement).");

const kAccounts = [
  {email: "merchant.test@proxiplay.test", password: "Test-Merchant-2026!", role: "commercant", name: "Boulangerie Test"},
  {email: "player.test@proxiplay.test", password: "Test-Player-2026!", role: "joueur", name: "Joueur Test"},
];

async function signUp({email, password}) {
  const base = `http://${kAuthHost}/identitytoolkit.googleapis.com/v1`;
  let res = await fetch(`${base}/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  if (!res.ok) {
    res = await fetch(`${base}/accounts:signInWithPassword?key=fake-api-key`, {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({email, password, returnSecureToken: true}),
    });
  }
  const body = await res.json();
  if (!body.localId) throw new Error(`Compte emulateur impossible: ${JSON.stringify(body)}`);
  return body.localId;
}

async function writeDoc(path, fields) {
  const url = `http://${kFirestoreHost}/v1/projects/${kProjectId}/databases/(default)/documents/${path}`;
  const res = await fetch(url, {
    method: "PATCH",
    headers: {"Content-Type": "application/json", "Authorization": "Bearer owner"},
    body: JSON.stringify({fields}),
  });
  if (!res.ok) throw new Error(`Ecriture ${path}: ${res.status} ${await res.text()}`);
}

const str = (value) => ({stringValue: value});
const ref = (path) => ({referenceValue: `projects/${kProjectId}/databases/(default)/documents/${path}`});

(async () => {
  for (const account of kAccounts) {
    const uid = await signUp(account);
    await writeDoc(`users/${uid}`, {
      email: str(account.email), display_name: str(account.name), user_role: str(account.role),
      ...(account.role === "commercant" ? {account_status: str("approved")} : {}),
    });
    if (account.role === "commercant") {
      await writeDoc(`enseignes/seed_${uid}_1`, {name: str("Boulangerie du port"), owner: ref(`users/${uid}`)});
      await writeDoc(`enseignes/seed_${uid}_2`, {name: str("Boulangerie du centre"), owner: ref(`users/${uid}`)});
    }
    console.log(`${account.role}: ${account.email} (uid ${uid})`);
  }
})().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
