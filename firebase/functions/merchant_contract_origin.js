// Origine d'une souscription (CGV B2B V2.1, art. 4.2). Lot 1.1 : version
// minimale, toute demande est spontanee ; le lot 1.4b ajoute le lien
// nominatif, le code de commercial, la case « visite » et le signalement.

const {httpsError} = require("./merchant_contracts_model");

async function resolveOrigin() {
  return {type: "spontanee", evidence: {sources: []}, prefill: null};
}

function markRepLinkUsed() {}

async function validateRepIdForCode(db, repId) {
  if (repId === undefined || repId === null || repId === "") return null;
  throw httpsError("invalid-argument", "Rattachement a un commercial indisponible.", {reason: "invalid_field", field: "repId"});
}

module.exports = {resolveOrigin, markRepLinkUsed, validateRepIdForCode};
