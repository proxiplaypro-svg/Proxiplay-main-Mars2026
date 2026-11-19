// Outils communs aux tests de la phase 1, tranche 1 (emulateur Firestore,
// projet demo- uniquement). Aucun e-mail reel : l'envoi est remplace par un
// enregistreur en memoire.
process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'demo-proxiplay-merchant-contracts';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`Projet ${process.env.GCLOUD_PROJECT} refuse : tests sur projet demo- uniquement.`);
}
const crypto = require('node:crypto');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const kCgvBytes = Buffer.from('%PDF-1.4\n% CGV V2.1 factices pour les tests\n');
const kCgvSha256 = crypto.createHash('sha256').update(kCgvBytes).digest('hex');
const kCgv = {
  version: '2.1',
  sha256: kCgvSha256,
  storage_path: 'legal/cgv/CGV_V2.1.pdf',
  url: 'https://www.proxiplay.fr/legal-content/sections/CGV.pdf',
  effective_date: '2026-12-01',
};

async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const project = process.env.GCLOUD_PROJECT;
  const response = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: 'DELETE'});
  if (!response.ok) throw new Error(`clearFirestore: ${response.status}`);
}

async function setConfig(overrides = {}) {
  await db.doc('app_config/merchant_contracts').set({
    enabled: true, cgv: kCgv, admin_alert_email: 'alertes@proxiplay.test', ...overrides,
  });
}

async function seedMerchant(uid = 'merchant', extra = {}) {
  await db.doc(`users/${uid}`).set({user_role: 'commercant', account_status: 'approved', email: `${uid}@example.test`, ...extra});
}

async function seedAdmin(uid = 'admin') {
  await db.doc(`users/${uid}`).set({user_role: 'admin', email: 'admin@example.test'});
}

async function seedEnseigne(id, ownerUid, extra = {}) {
  await db.doc(`enseignes/${id}`).set({
    name: `Boutique ${id}`, address: '1 rue de la Paix', city: 'Dunkerque', area_code: '59240',
    owner: db.doc(`users/${ownerUid}`), ...extra,
  });
}

function merchantContext(uid = 'merchant', ip = '203.0.113.7') {
  return {auth: {uid, token: {email: `${uid}@example.test`}}, rawRequest: {ip, headers: {}}};
}

function adminContext(uid = 'admin') {
  return {auth: {uid, token: {admin: true, email: 'admin@example.test'}}};
}

/** Remplace l'envoi des e-mails par un enregistreur ; renvoie la liste. */
function captureMail(mailModule, {fail = false} = {}) {
  const sent = [];
  mailModule.setSender(async (message) => {
    if (fail) throw new Error('smtp indisponible (test)');
    sent.push(message);
    return {messageId: `<test-${sent.length}@proxiplay.test>`};
  });
  return sent;
}

/** Instantane complet de la base (pour prouver qu'un appel n'a rien ecrit). */
async function snapshotAll() {
  const out = {};
  async function walk(collections) {
    for (const collection of collections) {
      const snap = await collection.get();
      for (const doc of snap.docs) {
        out[doc.ref.path] = JSON.stringify(doc.data());
        await walk(await doc.ref.listCollections());
      }
    }
  }
  await walk(await db.listCollections());
  return out;
}

async function rejectsWith(promise, reason) {
  let error = null;
  try {
    await promise;
  } catch (caught) {
    error = caught;
  }
  if (!error) throw new Error(`attendu : refus ${reason}`);
  if (reason && error.details?.reason !== reason && error.code !== reason) {
    throw new Error(`attendu ${reason}, recu ${error.code} ${error.details?.reason || ''} ${error.message}`);
  }
  return error;
}

module.exports = {
  admin, db, kCgv, kCgvBytes, kCgvSha256,
  clearFirestore, setConfig, seedMerchant, seedAdmin, seedEnseigne,
  merchantContext, adminContext, captureMail, snapshotAll, rejectsWith,
};
