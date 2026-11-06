const functions = require('firebase-functions');
const admin = require('firebase-admin');
const kTextVersion = 'marketing-player-v1';
const kMinimumNewsletterAge = 15;

function readBirthdayDate(value) {
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return value instanceof Date && !Number.isNaN(value.getTime()) ? value : null;
}

function isAtLeastAge(birthday, minimumAge, now = new Date()) {
  const anniversary = new Date(now);
  anniversary.setFullYear(now.getFullYear() - minimumAge);
  return birthday <= anniversary;
}

exports.setMarketingConsent = functions.region('us-central1').https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
  if (typeof data?.enabled !== 'boolean') throw new functions.https.HttpsError('invalid-argument', 'Choix invalide.');
  if (data?.textVersion !== kTextVersion) throw new functions.https.HttpsError('invalid-argument', 'Version de consentement invalide.');
  if (!['signup', 'player-profile'].includes(data?.source)) throw new functions.https.HttpsError('invalid-argument', 'Origine invalide.');
  const db = admin.firestore(), user = db.doc(`users/${context.auth.uid}`), event = user.collection('marketing_consent_events').doc();
  await db.runTransaction(async tx => {
    const current = await tx.get(user);
    if (!current.exists) throw new functions.https.HttpsError('failed-precondition', 'Profil joueur introuvable.');
    const userData = current.data() || {};
    if (data.enabled) {
      const birthday = readBirthdayDate(userData.birthday);
      if (!birthday || !isAtLeastAge(birthday, kMinimumNewsletterAge)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Votre éligibilité aux communications promotionnelles ne peut pas être établie.',
        );
      }
    }
    // Les futurs envois doivent exiger enabled == true ET cette éligibilité.
    const consent = {
      enabled: data.enabled,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      text_version: kTextVersion,
      source: data.source,
      newsletter_eligibility: data.enabled
        ? 'age_15_plus_confirmed'
        : 'not_subscribed',
    };
    tx.set(user, { marketing_consent: consent }, { merge: true });
    tx.create(event, { ...consent, event_type: data.enabled ? 'granted' : 'withdrawn', retention_until: admin.firestore.Timestamp.fromMillis(Date.now() + 3 * 365 * 24 * 60 * 60 * 1000) });
  });
  return { enabled: data.enabled };
});

exports._test = { isAtLeastAge, readBirthdayDate };
