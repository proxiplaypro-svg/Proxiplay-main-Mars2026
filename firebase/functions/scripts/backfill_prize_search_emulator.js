// Isolated emulator only. Production migration requires a separately reviewed tool.
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw new Error('An isolated demo Firestore emulator is required');
}
if (!admin.apps.length) admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const {syncPrizeSearchCodeCore} = require('../merchant_prizes');
(async () => {
  let cursor, count=0;
  do {
    let query=db.collection('prizes').orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if(cursor) query=query.startAfter(cursor);
    const page=await query.get();
    for(const doc of page.docs) { await syncPrizeSearchCodeCore(doc.ref); count++; }
    cursor=page.size===100?page.docs[page.size-1]:null;
  } while(cursor);
  process.stdout.write(`Processed ${count} fictitious prize documents.\n`);
})().catch(()=>{process.stderr.write('Emulator backfill failed.\n');process.exitCode=1;});
