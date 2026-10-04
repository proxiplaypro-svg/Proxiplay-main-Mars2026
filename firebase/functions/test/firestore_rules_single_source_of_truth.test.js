// Garde-fou structurel : empeche le retour accidentel d'un second jeu de
// regles Firestore deployable. Contexte complet dans le rapport du chantier
// claude/remove-legacy-firestore-rules -- firebase.rollout.json pointait
// vers firebase/firestore.legacy-prizes.rules, un fichier de regles
// parallele cree comme pont de compatibilite temporaire (09/09/2026) puis
// jamais tenu a jour : au moment de sa suppression il avait deja trois
// correctifs de securite de retard sur firebase/firestore.rules (garde
// anti-reactivation d'un jeu finalise, creation marchand securisee,
// confidentialite des lots partenaire/plateforme). Le risque n'etait pas
// l'automatisation (aucun script/CI ne le referencait) mais la copie d'une
// commande de runbook perimee (`firebase deploy --only firestore:rules
// --config firebase.rollout.json`) sans revoir son contenu reel.
//
// Ce test echoue si :
//  - firebase.rollout.json reapparait ;
//  - firebase/firestore.legacy-prizes.rules reapparait ;
//  - un futur fichier de config Firebase (firebase*.json a la racine)
//    declare des regles Firestore differentes de firebase/firestore.rules ;
//  - un fichier .rules autre que firestore.rules/storage.rules existe sous
//    firebase/ (couvre un fichier renomme, pas seulement les deux noms
//    actuels).
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../../..");
const CANONICAL_FIRESTORE_RULES = "firebase/firestore.rules";

test("firebase.rollout.json n'existe plus", () => {
  assert.equal(
    fs.existsSync(path.join(repoRoot, "firebase.rollout.json")),
    false,
    "firebase.rollout.json a ete supprime deliberement -- voir claude/remove-legacy-firestore-rules",
  );
});

test("firebase/firestore.legacy-prizes.rules n'existe plus", () => {
  assert.equal(
    fs.existsSync(path.join(repoRoot, "firebase", "firestore.legacy-prizes.rules")),
    false,
    "firestore.legacy-prizes.rules a ete supprime deliberement -- voir claude/remove-legacy-firestore-rules",
  );
});

test("aucun fichier de config Firebase a la racine ne declare de regles Firestore autres que le fichier canonique", () => {
  const configFiles = fs
    .readdirSync(repoRoot)
    .filter((name) => /^firebase.*\.json$/i.test(name));

  assert.ok(configFiles.includes("firebase.json"), "firebase.json canonique doit exister");

  const offenders = [];
  for (const fileName of configFiles) {
    const raw = fs.readFileSync(path.join(repoRoot, fileName), "utf8");
    const parsed = JSON.parse(raw);
    const declaredRules = parsed?.firestore?.rules;
    if (declaredRules != null && declaredRules !== CANONICAL_FIRESTORE_RULES) {
      offenders.push(`${fileName} -> firestore.rules="${declaredRules}"`);
    }
  }

  assert.deepEqual(
    offenders, [],
    `Chaque firebase*.json declarant des regles Firestore doit pointer sur ${CANONICAL_FIRESTORE_RULES} : ${offenders.join(", ")}`,
  );
});

test("aucun fichier .rules parasite sous firebase/ (seuls firestore.rules et storage.rules sont attendus)", () => {
  const firebaseDir = path.join(repoRoot, "firebase");
  const rulesFiles = fs
    .readdirSync(firebaseDir)
    .filter((name) => name.endsWith(".rules"))
    .sort();

  assert.deepEqual(
    rulesFiles,
    ["firestore.rules", "storage.rules"],
    "Un fichier .rules supplementaire sous firebase/ est un second jeu de regles potentiellement deployable -- a justifier explicitement, pas a laisser trainer silencieusement.",
  );
});
