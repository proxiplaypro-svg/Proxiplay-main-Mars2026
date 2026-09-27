const crypto = require('crypto');

function newClaimCode() {
  // 80 bits: human-copyable hexadecimal and sufficiently strong even at
  // production volume. The registry below provides the actual uniqueness
  // guarantee, including against historical prizes without a registry row.
  return crypto.randomBytes(10).toString('hex').toUpperCase();
}

async function reserveClaimCode(transaction, db, {generate = newClaimCode, attempts = 12} = {}) {
  for (let i = 0; i < attempts; i += 1) {
    const code = String(generate()).trim().toUpperCase();
    if (!/^[A-Z0-9]{8,128}$/.test(code)) throw Error('Generated invalid claim code');
    const registry = db.doc(`_claim_code_registry/${code}`);
    const [reserved, historical] = await Promise.all([
      transaction.get(registry),
      transaction.get(db.collection('prizes').where('claim_code', '==', code).limit(1)),
    ]);
    if (reserved.exists || !historical.empty) continue;
    transaction.create(registry, {created_at: new Date(), code_version: 2});
    return code;
  }
  throw Error('Unable to reserve a unique claim code');
}

module.exports = {newClaimCode, reserveClaimCode};
