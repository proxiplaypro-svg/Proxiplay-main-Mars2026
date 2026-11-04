// Source de la configuration SMTP des fonctions de l'app.
// 1. Variables d'environnement SMTP_* (fichier .env.<projet> déployé avec les fonctions),
//    utilisées dès que SMTP_HOST est renseigné.
// 2. Sinon, repli sur functions.config().smtp (Runtime Config, API dépréciée).
// Les deux sources ne sont jamais mélangées : une configuration partielle doit échouer
// dans getSmtpSettings plutôt que d'assembler hôte et identifiants d'origines différentes.

const kEnvKeys = {
  host: "SMTP_HOST",
  port: "SMTP_PORT",
  secure: "SMTP_SECURE",
  user: "SMTP_USER",
  pass: "SMTP_PASS",
  from_email: "SMTP_FROM_EMAIL",
  from_name: "SMTP_FROM_NAME",
  reply_to: "SMTP_REPLY_TO",
};

let loggedSource = null;

function defaultLoadRuntimeConfig() {
  return require("firebase-functions").config();
}

function readSmtpConfig({env = process.env, loadRuntimeConfig = defaultLoadRuntimeConfig} = {}) {
  const fromEnv = typeof env.SMTP_HOST === "string" && env.SMTP_HOST.trim() !== "";
  let source = "env";
  let smtpConfig = {};
  if (fromEnv) {
    for (const [key, envName] of Object.entries(kEnvKeys)) {
      if (env[envName] !== undefined) smtpConfig[key] = env[envName];
    }
  } else {
    source = "runtime_config";
    try {
      smtpConfig = (loadRuntimeConfig() || {}).smtp || {};
    } catch (error) {
      smtpConfig = {};
    }
    if (Object.keys(smtpConfig).length === 0) source = "none";
  }
  if (loggedSource !== source) {
    loggedSource = source;
    console.log(`[smtp_config] source=${source}`);
  }
  return smtpConfig;
}

module.exports = {readSmtpConfig};
