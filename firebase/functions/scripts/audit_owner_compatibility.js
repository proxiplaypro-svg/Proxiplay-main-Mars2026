// Offline dry-run only. Input: JSON array of {id, owner, owner_id} exported
// locally; references must be represented as {path: 'users/uid'}.
// This module has no Firebase dependency, credentials, network or apply mode.
const fs = require('node:fs');
const {shopOwnerPath} = require('../merchant_ownership');
function auditOwners(rows) {
  if (!Array.isArray(rows)) throw Error('Expected an array of enseigne records');
  return rows.map(row => {
    const ownerPath = shopOwnerPath(row);
    const canonical = value => value && typeof value === 'object' && value.path === ownerPath;
    return {id: row.id, status: !ownerPath ? 'manual_review' :
      canonical(row.owner) && canonical(row.owner_id) ? 'canonical' : 'compatible_normalization',
    proposedOwnerPath: ownerPath || null};
  });
}
if (require.main === module) {
  if (process.argv.length !== 3 || process.argv[2].startsWith('--')) {
    throw Error('Usage: node audit_owner_compatibility.js local-export.json (no apply mode)');
  }
  console.log(JSON.stringify(auditOwners(JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))), null, 2));
}
module.exports = {auditOwners};
