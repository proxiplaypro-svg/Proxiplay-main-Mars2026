// Explicit targeted migration; defaults to dry run. No collection-wide write mode.
const admin=require('firebase-admin');
async function main(){
 const args=process.argv.slice(2);
 const project=args.find(a=>a.startsWith('--project='))?.slice(10);
 const type=args.find(a=>a.startsWith('--type='))?.slice(7);
 const id=args.find(a=>a.startsWith('--id='))?.slice(5);
 if(!project||!['prize','animation'].includes(type)||!id||id.includes('/')) throw Error('Required: --project=ID --type=prize|animation --id=ID [--apply]');
 admin.initializeApp({projectId:project});
 const {syncPublicPrize,backfillAnimationWinner}=require('../public_winners');
 const apply=args.includes('--apply');
 const result=type==='prize'?await syncPublicPrize(id,{createOnly:true,apply}):await backfillAnimationWinner(id,{apply});
 console.log(JSON.stringify({project,type,id,apply,...result}));
}
if(require.main===module) main().catch(error=>{console.error(error.message);process.exitCode=1;});
