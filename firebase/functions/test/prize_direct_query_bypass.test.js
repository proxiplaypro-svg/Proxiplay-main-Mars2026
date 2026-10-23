const test=require('node:test'); const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertSucceeds}=require('@firebase/rules-unit-testing');
if(!process.env.FIRESTORE_EMULATOR_HOST||!String(process.env.GCLOUD_PROJECT||'').startsWith('demo-')) throw Error('isolated demo emulator required');
test('legacy direct owner listing bypasses callable rate limit',async()=>{
 const env=await initializeTestEnvironment({projectId:process.env.GCLOUD_PROJECT,firestore:{rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.rules'),'utf8')}});
 try {
  await env.withSecurityRulesDisabled(async c=>{const db=c.firestore();await db.doc('prizes/p').set({owner_id:db.doc('users/merchant'),claim_code:'TEST'});});
  const db=env.authenticatedContext('merchant').firestore();
  await assertSucceeds(db.collection('prizes').where('owner_id','==',db.doc('users/merchant')).get());
 } finally {await env.cleanup();}
});
