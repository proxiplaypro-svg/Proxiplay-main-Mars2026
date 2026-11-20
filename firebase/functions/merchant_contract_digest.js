// Version minimale (decision du 20 novembre 2026) : suivi manuel par l'admin.
// Digest quotidien : UNE tache planifiee (heure de Paris) qui envoie UN
// e-mail a l'adresse des alertes de app_config/merchant_contracts, avec ce
// que l'admin doit traiter a la main :
//   - contrats demarches dont le delai de retractation est ecoule, sans
//     invitation a payer envoyee ;
//   - liens de paiement qui expirent dans 3 jours, ou expires sans cloture ;
//   - renouvellements dans 45 jours (rappel art. 9) et dans 15 jours ;
//   - delais de regularisation (grace) en cours ou termines ;
//   - alertes non traitees (stripe_unmatched_events, admin_alerts) ;
//   - e-mails en file de reprise (mail_outbox).
// Lecture seule : aucune ecriture Firestore, aucun appel Stripe. Aucun e-mail
// si la liste est vide. Independant de l'interrupteur (suivi des contrats
// existants). Echec SMTP : journalise (Cloud Logging) et rejete, pour que
// Cloud Scheduler retente ; rien n'est ecrit (le digest du lendemain reprend
// tout, puisqu'il est recalcule a chaque fois).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  readContractsConfig,
  millisOf,
} = require("./merchant_contracts_model");
const mail = require("./merchant_contract_mail");
const {euros, parisDate: dateLabel, enseigneLabel, kConsoleUrl, kSignature} = require("./merchant_contract_emails");
const {parisDate, addDays, endOfParisDay} = require("./paris_time");
const {kGraceStatuses} = require("./merchant_billing_access");

const kDayMs = 24 * 60 * 60 * 1000;
const kExpirySoonDays = 3;
const kRenewalNoticeDays = 45;
const kRenewalLateDays = 15;
const kMaxLinesPerSection = 50;
const kSubscriptionsCollection = "enseigne_subscriptions";
const kUnmatchedEventsCollection = "stripe_unmatched_events";
const kRenewingStatuses = Object.freeze(["active", "trialing"]);

/** Nombre de jours calendaires (Paris) entre deux instants. */
function parisDaysBetween(fromMs, toMs) {
  const a = parisDate(fromMs);
  const b = parisDate(toMs);
  return Math.round((Date.UTC(b.y, b.m - 1, b.d) - Date.UTC(a.y, a.m - 1, a.d)) / kDayMs);
}

/** Date limite (fin du jour, Paris) d'un rappel envoye `days` jours avant l'echeance. */
function reminderDeadline(renewalMs, days) {
  return endOfParisDay(addDays(parisDate(renewalMs), -days));
}

function contractLabel(id, contract) {
  return `${enseigneLabel(contract) || "(enseigne ?)"} · ${contract.owner_email || "e-mail ?"} · demande ${id}`;
}

/** Collecte en lecture seule. Renvoie {sections: [{title, hint, lines}], total}. */
async function collectDigest(db, nowMs) {
  const [withdrawalSnap, invitedSnap, subsSnap, unmatchedSnap, alertsSnap, outboxPending, outboxFailed] = await Promise.all([
    db.collection(kContractsCollection).where("state", "==", kStates.WITHDRAWAL_PENDING).get(),
    db.collection(kContractsCollection).where("state", "==", kStates.PAYMENT_INVITED).get(),
    db.collection(kSubscriptionsCollection).where("status", "in", [...kRenewingStatuses, ...kGraceStatuses]).get(),
    db.collection(kUnmatchedEventsCollection).where("resolved", "==", false).get(),
    db.collection(mail.kAdminAlertsCollection).where("resolved", "==", false).get(),
    db.collection(mail.kOutboxCollection).where("status", "==", "pending").get(),
    db.collection(mail.kOutboxCollection).where("status", "==", "failed").get(),
  ]);

  const withdrawalDone = [];
  for (const doc of withdrawalSnap.docs) {
    const c = doc.data();
    const deadlineMs = millisOf(c.withdrawal_deadline);
    if (!deadlineMs || deadlineMs > nowMs) continue;
    withdrawalDone.push([deadlineMs, `${contractLabel(doc.id, c)} · délai écoulé le ${dateLabel(deadlineMs)}`]);
  }

  const expiringSoon = [];
  const expired = [];
  for (const doc of invitedSnap.docs) {
    const c = doc.data();
    const expiresMs = millisOf(c.payment_link_expires_at);
    if (!expiresMs) continue;
    const line = `${contractLabel(doc.id, c)} · lien envoyé le ${dateLabel(millisOf(c.payment_invited_at))}, ` +
      `valable jusqu'au ${dateLabel(expiresMs)}`;
    if (expiresMs <= nowMs) expired.push([expiresMs, line]);
    else if (expiresMs <= nowMs + kExpirySoonDays * kDayMs) expiringSoon.push([expiresMs, line]);
  }

  // Abonnements suivis : contrat lu pour l'enseigne, l'adresse et le prix.
  const contractIds = [...new Set(subsSnap.docs.map((d) => d.data().contract_id).filter(Boolean))];
  const contractDocs = contractIds.length ?
    await db.getAll(...contractIds.map((id) => db.collection(kContractsCollection).doc(id))) : [];
  const contracts = new Map(contractDocs.filter((d) => d.exists).map((d) => [d.id, d.data()]));
  const renewal45 = [];
  const renewal15 = [];
  const graceOngoing = [];
  const graceEnded = [];
  for (const doc of subsSnap.docs) {
    const s = doc.data();
    if (!s.stripe_subscription_id) continue;
    const c = contracts.get(s.contract_id) || {enseigne_name: doc.id};
    const label = contractLabel(s.contract_id || "?", c);
    if (kGraceStatuses.includes(s.status)) {
      const graceMs = millisOf(s.grace_until);
      const invoice = s.last_failed_invoice_id ? ` · facture ${s.last_failed_invoice_id}` : "";
      if (graceMs && graceMs <= nowMs) {
        graceEnded.push([graceMs, `${label} · Stripe ${s.status} · délai terminé le ${dateLabel(graceMs)}${invoice}`]);
      } else {
        graceOngoing.push([graceMs || 0, `${label} · Stripe ${s.status} · délai jusqu'au ${dateLabel(graceMs) || "?"}${invoice}`]);
      }
      continue;
    }
    if (s.cancel_at_period_end === true) continue;
    const renewalMs = millisOf(s.current_period_end);
    if (!renewalMs || renewalMs <= nowMs) continue;
    const days = parisDaysBetween(nowMs, renewalMs);
    const amount = c.offer?.renewal_ttc_cents ? ` · ${euros(c.offer.renewal_ttc_cents)} TTC` : "";
    if (days <= kRenewalLateDays) {
      renewal15.push([renewalMs, `${label} · échéance le ${dateLabel(renewalMs)} (J-${days})${amount}`]);
    } else if (days <= kRenewalNoticeDays + 1) {
      const deadlineMs = reminderDeadline(renewalMs, kRenewalNoticeDays);
      const late = deadlineMs < nowMs ? " · DATE DU RAPPEL DÉPASSÉE" : "";
      renewal45.push([renewalMs, `${label} · échéance le ${dateLabel(renewalMs)} (J-${days})${amount} · ` +
        `rappel art. 9 au plus tard le ${dateLabel(deadlineMs)}${late}`]);
    }
  }

  const unmatched = unmatchedSnap.docs.map((d) => {
    const e = d.data();
    return [millisOf(e.created_at) || 0, `${e.event_type || "?"} (${e.event_id || d.id}) · ${e.outcome || "?"}` +
      `${e.reason ? ` (${e.reason})` : ""}${e.contract_id ? ` · demande ${e.contract_id}` : ""} · ${dateLabel(millisOf(e.created_at), true)}`];
  });
  const alerts = alertsSnap.docs.map((d) => {
    const a = d.data();
    return [millisOf(a.created_at) || 0, `${a.kind || "?"} · ${String(a.detail || "").slice(0, 160)}` +
      `${a.contract_id ? ` · demande ${a.contract_id}` : ""} · ${dateLabel(millisOf(a.created_at), true)}`];
  });
  const outbox = [...outboxPending.docs, ...outboxFailed.docs].map((d) => {
    const o = d.data();
    const status = o.status === "failed" ? "ABANDONNÉ après les tentatives" : `en attente (${o.attempts || 0} tentative(s))`;
    return [millisOf(o.created_at) || 0, `« ${o.key || o.kind || "?"} » · ${status}` +
      `${o.contract_id ? ` · demande ${o.contract_id}` : ""} · ${String(o.last_error || "").slice(0, 120)}`];
  });

  const sections = [
    {title: "Rétractation écoulée, invitation à payer non envoyée (démarchage)", lines: withdrawalDone,
      hint: "Envoyer l'invitation depuis la console (bouton « Envoyer l'invitation »)."},
    {title: `Liens de paiement qui expirent dans ${kExpirySoonDays} jours`, lines: expiringSoon,
      hint: "Relancer le commerçant si besoin."},
    {title: "Liens de paiement expirés, contrat non clôturé", lines: expired,
      hint: "Décider : nouveau lien, ou clôture manuelle (rien n'a été facturé)."},
    {title: `Renouvellements dans ${kRenewalNoticeDays} jours ou moins (rappel de l'art. 9)`, lines: renewal45,
      hint: "Envoyer le rappel (date, montant, comment désactiver) avant la date indiquée."},
    {title: `Renouvellements dans ${kRenewalLateDays} jours ou moins`, lines: renewal15,
      hint: "Vérifier que le rappel est parti ; une désactivation demandée se fait dans Stripe."},
    {title: "Délais de régularisation en cours", lines: graceOngoing,
      hint: "Relances manuelles si besoin (facture Stripe en ligne)."},
    {title: "Délais de régularisation terminés", lines: graceEnded,
      hint: "Décider : suspension, mise en demeure, résiliation (art. 11)."},
    {title: "Événements Stripe non rattachés (stripe_unmatched_events)", lines: unmatched,
      hint: "Aucune action automatique sur l'argent : décision manuelle dans Stripe."},
    {title: "Alertes non traitées (admin_alerts)", lines: alerts,
      hint: "Traiter puis marquer « traitée » dans la console."},
    {title: "E-mails en file de reprise (mail_outbox)", lines: outbox,
      hint: "Relancer ou abandonner depuis la console ; un e-mail abandonné est à envoyer à la main."},
  ].map((section) => ({
    ...section,
    lines: section.lines.sort((a, b) => a[0] - b[0]).map(([, line]) => line),
  }));
  return {sections, total: sections.reduce((sum, s) => sum + s.lines.length, 0)};
}

function digestMessage(to, digest, nowMs) {
  const parts = [];
  for (const section of digest.sections) {
    if (!section.lines.length) continue;
    const shown = section.lines.slice(0, kMaxLinesPerSection);
    const more = section.lines.length - shown.length;
    parts.push(`■ ${section.title} : ${section.lines.length}\n${section.hint}\n` +
      shown.map((line) => `  - ${line}`).join("\n") + (more > 0 ? `\n  … et ${more} autre(s), voir la console.` : ""));
  }
  return {
    to,
    subject: `[ProxiPlay] Suivi des souscriptions du ${dateLabel(nowMs)} : ${digest.total} point(s) à traiter`,
    text: `Suivi manuel des souscriptions (CGV V2.1), état au ${dateLabel(nowMs, true)} (heure de Paris).\n\n` +
      `${parts.join("\n\n")}\n\nDétail : ${kConsoleUrl}.\nCe message est envoyé chaque jour s'il reste un point à traiter.\n\n${kSignature}`,
  };
}

/** Une execution : collecte, puis un seul e-mail si la liste n'est pas vide. */
async function runMerchantContractDigest({db = admin.firestore(), nowMs = Date.now()} = {}) {
  const config = await readContractsConfig(db);
  const digest = await collectDigest(db, nowMs);
  const counts = Object.fromEntries(digest.sections.map((s, i) => [i, s.lines.length]));
  if (digest.total === 0) return {sent: false, total: 0, counts};
  try {
    await mail.sendContractMail(digestMessage(config.adminAlertEmail, digest, nowMs));
  } catch (error) {
    console.error("[merchant_contracts] digest non envoye", String(error?.message || error).slice(0, 300));
    throw error;
  }
  return {sent: true, total: digest.total, counts};
}

exports.merchantContractDigest = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .pubsub.schedule("0 8 * * *")
  .timeZone("Europe/Paris")
  .retryConfig({retryCount: 3, minBackoffDuration: "600s"})
  .onRun(async () => {
    const stats = await runMerchantContractDigest();
    console.log("[merchant_contracts] digest", JSON.stringify(stats));
    return null;
  });

exports.runMerchantContractDigest = runMerchantContractDigest;
exports.collectDigest = collectDigest;
exports.digestMessage = digestMessage;
exports.parisDaysBetween = parisDaysBetween;
