// Adds claim_code_search to historical prizes so that searchMerchantPrizeCodes
// can suggest codes created before the syncPrizeSearchCode trigger existed.
//
// Dry run by default: it only counts the prizes that would change.
//   node scripts/backfill_prize_search_codes.js --project <projectId>
// Writing requires an explicit flag, after indexes and functions are deployed:
//   node scripts/backfill_prize_search_codes.js --project <projectId> --apply
// It only sets claim_code_search (a normalized copy of claim_code) and is
// idempotent: a second run changes nothing.
//
// By default only prizes a merchant can still be offered are migrated
// (unclaimed, not expired, merchant-delivered, attached to an account or a
// shop): claimed or expired codes are never suggested, so they do not need
// the field. --all migrates every prize and must be requested explicitly.
// --won-within-days N further limits it to prizes won in the last N days;
// older codes stay verifiable by typing the full code (exact search).
const admin = require('firebase-admin');
const args = process.argv.slice(2);
const projectId = args[args.indexOf('--project') + 1];
const apply = args.includes('--apply');
const all = args.includes('--all');
const withinIndex = args.indexOf('--won-within-days');
const wonWithinDays = withinIndex >= 0 ? Number(args[withinIndex + 1]) : null;
// Controlled trial: --limit N stops after N prizes, --owner <uid> keeps only
// prizes whose owner_id is that merchant account.
const limitIndex = args.indexOf('--limit');
const limit = limitIndex >= 0 ? Number(args[limitIndex + 1]) : null;
const ownerIndex = args.indexOf('--owner');
const ownerPath = ownerIndex >= 0 ? 'users/' + args[ownerIndex + 1] : null;
if (limitIndex >= 0 && !(Number.isInteger(limit) && limit > 0)) {
  process.stderr.write('--limit needs a positive integer\n');
  process.exit(2);
}
if (withinIndex >= 0 && !(wonWithinDays > 0)) {
  process.stderr.write('--won-within-days needs a positive number of days\n');
  process.exit(2);
}
if (!args.includes('--project') || !projectId || projectId.startsWith('--')) {
  process.stderr.write('Usage: --project <projectId> [--apply] [--all]\n');
  process.exit(2);
}
if (!admin.apps.length) admin.initializeApp({projectId});
const db = admin.firestore();
const {normalizePrizeSearchCode, isSuggestiblePrize} = require('../merchant_prizes');

(async () => {
  const now = Date.now();
  const wonSince = wonWithinDays ? now - wonWithinDays * 86400000 : null;
  let cursor, scanned = 0, pending = 0, written = 0, skippedNotSuggestible = 0, skippedOlder = 0;
  const updatedIds = [];
  do {
    let query = db.collection('prizes').orderBy(admin.firestore.FieldPath.documentId()).limit(300);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    const batch = db.batch();
    let batchSize = 0;
    for (const doc of page.docs) {
      scanned++;
      const data = doc.data();
      const code = normalizePrizeSearchCode(data.claim_code);
      if (!code || data.claim_code_search === code) continue;
      if (!all && !isSuggestiblePrize(data, now)) { skippedNotSuggestible++; continue; }
      if (wonSince != null && !((data.win_date?.toMillis?.() ?? 0) >= wonSince)) { skippedOlder++; continue; }
      if (ownerPath && data.owner_id?.path !== ownerPath) continue;
      if (limit != null && pending >= limit) break;
      pending++;
      if (apply) { batch.update(doc.ref, {claim_code_search: code}); batchSize++; updatedIds.push(doc.id); }
    }
    if (batchSize) { await batch.commit(); written += batchSize; }
    cursor = page.size === 300 && !(limit != null && pending >= limit) ? page.docs[page.size - 1] : null;
  } while (cursor);
  process.stdout.write(JSON.stringify({projectId, apply, all, wonWithinDays, limit, owner: ownerPath,
    scanned, pending, written, skippedNotSuggestible, skippedOlder,
    ...(limit != null ? {updatedIds} : {})}) + '\n');
})().catch(error => {
  process.stderr.write(`Backfill failed: ${error.code || error.message}\n`);
  process.exitCode = 1;
});
