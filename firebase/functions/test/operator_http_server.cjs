// Real Firebase onCall HTTP handler, not a mocked callable. Local tests only.
// Auth token verification remains enabled and uses the Auth emulator.
if (process.env.GCLOUD_PROJECT !== 'demo-proxiplay-lifecycle' ||
    process.env.FIREBASE_DEBUG_MODE === 'true' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
  throw Error('Local demo emulators required');
}
const admin = require('firebase-admin');
admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const app = require('express')();
app.use(require('express').json());
app.post('/demo-proxiplay-lifecycle/us-central1/claimOperatorPrize',
  require('../operator_prize_claim').claimOperatorPrize);
app.listen(5001, '127.0.0.1', () => console.log('Operator onCall HTTP handler ready on localhost:5001'));
