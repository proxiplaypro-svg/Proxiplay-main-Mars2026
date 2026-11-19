// PDF date des CGV en vigueur, joint a la confirmation de souscription (art.
// 4.3). Lu dans Cloud Storage (bucket par defaut du projet) au chemin
// app_config/merchant_contracts.cgv.storage_path ; son empreinte SHA-256 doit
// correspondre a cgv.sha256, sinon aucune confirmation ne part.

const crypto = require("crypto");
const admin = require("firebase-admin");

let customLoader = null;

/** Tests uniquement : remplace la lecture Storage (null = comportement normal). */
function setLoader(loader) {
  customLoader = typeof loader === "function" ? loader : null;
}

async function loadCgvPdf(storagePath) {
  if (customLoader) return customLoader(storagePath);
  const [content] = await admin.storage().bucket().file(storagePath).download();
  return content;
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

module.exports = {setLoader, loadCgvPdf, sha256};
