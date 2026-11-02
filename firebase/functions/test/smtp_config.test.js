#!/usr/bin/env node

const test = require("node:test");
const assert = require("node:assert/strict");

const {readSmtpConfig} = require("../lib/notifications/smtp_config");

const fullEnv = {
  SMTP_HOST: "smtp.env.example",
  SMTP_PORT: "465",
  SMTP_SECURE: "true",
  SMTP_USER: "env-user",
  SMTP_PASS: "env-pass",
  SMTP_FROM_EMAIL: "env@example.invalid",
  SMTP_FROM_NAME: "Env",
  SMTP_REPLY_TO: "reply@example.invalid",
};

const runtimeConfig = {
  smtp: {
    host: "smtp.runtime.example",
    port: "587",
    user: "runtime-user",
    pass: "runtime-pass",
    from_email: "runtime@example.invalid",
    from_name: "Runtime",
  },
};

test("SMTP_HOST renseigné : la configuration vient des variables d'environnement", () => {
  let runtimeCalls = 0;
  const config = readSmtpConfig({
    env: fullEnv,
    loadRuntimeConfig: () => {
      runtimeCalls += 1;
      return runtimeConfig;
    },
  });
  assert.deepEqual(config, {
    host: "smtp.env.example",
    port: "465",
    secure: "true",
    user: "env-user",
    pass: "env-pass",
    from_email: "env@example.invalid",
    from_name: "Env",
    reply_to: "reply@example.invalid",
  });
  assert.equal(runtimeCalls, 0, "Runtime Config ne doit pas être lue quand l'environnement suffit");
});

test("sans SMTP_HOST : repli sur functions.config().smtp", () => {
  const config = readSmtpConfig({env: {}, loadRuntimeConfig: () => runtimeConfig});
  assert.deepEqual(config, runtimeConfig.smtp);
});

test("SMTP_HOST vide : repli sur functions.config().smtp", () => {
  const config = readSmtpConfig({
    env: {SMTP_HOST: "  ", SMTP_PASS: "ignored"},
    loadRuntimeConfig: () => runtimeConfig,
  });
  assert.deepEqual(config, runtimeConfig.smtp);
});

test("les deux sources ne sont jamais mélangées", () => {
  const config = readSmtpConfig({
    env: {SMTP_HOST: "smtp.env.example"},
    loadRuntimeConfig: () => runtimeConfig,
  });
  assert.deepEqual(config, {host: "smtp.env.example"});
});

test("aucune source : objet vide, y compris si Runtime Config lève une erreur", () => {
  assert.deepEqual(readSmtpConfig({env: {}, loadRuntimeConfig: () => ({})}), {});
  assert.deepEqual(
    readSmtpConfig({
      env: {},
      loadRuntimeConfig: () => {
        throw new Error("Runtime Config indisponible");
      },
    }),
    {},
  );
});
