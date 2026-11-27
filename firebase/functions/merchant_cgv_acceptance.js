// Acceptation des CGV commerçant (case « J'accepte les CGV »).
// Écrite uniquement par le serveur (SDK Admin) :
// - users/{uid} : cgv_accepted_version, cgv_accepted_at (lus par l'app pour
//   savoir si l'écran CGV doit être affiché) ;
// - merchant_cgv_acceptances/{uid}/history/{version} : trace pour l'admin.
//   Aucune règle ne couvre cette collection : refusée par défaut aux clients.
// Aucune adresse IP n'est enregistrée.
const functions = require('firebase-functions');
const admin = require('firebase-admin');

const kFunctionsRegion = 'us-central1';

// Doivent rester identiques à lib/utils/merchant_cgv.dart (test dédié).
const kMerchantCgvVersion = '2.1';
const kMerchantCgvCheckboxText =
  "J'ai lu et j'accepte les conditions générales de vente PROXIPLAY " +
  '(version 2.1, applicables à compter du 1er décembre 2026).';
const kMerchantCgvUrl = 'https://www.proxiplay.fr/legal-content/sections/CGV.pdf';

const kSources = ['signup', 'login'];
const kUserAgentMaxLength = 300;

function readUserAgent(rawRequest) {
  const value = rawRequest && rawRequest.headers ? rawRequest.headers['user-agent'] : '';
  return typeof value === 'string' ? value.slice(0, kUserAgentMaxLength) : '';
}

async function readAuthEmail(uid) {
  try {
    const user = await admin.auth().getUser(uid);
    return user.email || '';
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') return '';
    throw error;
  }
}

exports.recordMerchantCgvAcceptance = functions
  .region(kFunctionsRegion)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
    }
    if (!data || data.accepted !== true) {
      throw new functions.https.HttpsError('invalid-argument', 'Acceptation des CGV requise.');
    }
    if (!kSources.includes(data.source)) {
      throw new functions.https.HttpsError('invalid-argument', 'Origine invalide.');
    }
    const uid = context.auth.uid;
    const db = admin.firestore();
    const userRef = db.doc(`users/${uid}`);
    const historyRef = db.doc(`merchant_cgv_acceptances/${uid}/history/${kMerchantCgvVersion}`);
    const email = await readAuthEmail(uid);
    const userAgent = readUserAgent(context.rawRequest);

    await db.runTransaction(async tx => {
      const [user, history] = await Promise.all([tx.get(userRef), tx.get(historyRef)]);
      if (!user.exists || (user.data() || {}).user_role !== 'commercant') {
        throw new functions.https.HttpsError('permission-denied', 'Réservé aux comptes commerçants.');
      }
      // Déjà acceptée pour cette version : succès idempotent, rien n'est réécrit
      // (la date d'origine est conservée).
      if (history.exists) return;
      const acceptedAt = admin.firestore.FieldValue.serverTimestamp();
      tx.create(historyRef, {
        uid,
        email,
        cgv_version: kMerchantCgvVersion,
        checkbox_text: kMerchantCgvCheckboxText,
        accepted_at: acceptedAt,
        source: data.source,
        user_agent: userAgent,
      });
      tx.update(userRef, {
        cgv_accepted_version: kMerchantCgvVersion,
        cgv_accepted_at: acceptedAt,
      });
    });
    return {accepted: true, version: kMerchantCgvVersion};
  });

exports._constants = {kMerchantCgvVersion, kMerchantCgvCheckboxText, kMerchantCgvUrl};
