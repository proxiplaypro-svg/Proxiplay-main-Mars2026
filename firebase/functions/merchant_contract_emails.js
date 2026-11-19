// Textes des e-mails du parcours de souscription (CGV B2B V2.1). Texte brut :
// le corps de l'e-mail est le support durable (art. 4.3). Aucun texte ne
// promet une fonction qui n'existe pas encore.

// Adresse de la console non fixee ici (domaine non verifie) : chemin seul.
const kConsoleUrl = "console admin, page Souscriptions (/admin/souscriptions)";
const kContactEmail = "contact@proxiplay.fr";
const kPostalAddress = "PROXIPLAY, 214 boulevard de la République François Mitterrand, 59240 Dunkerque";
const kSignature = "L'équipe ProxiPlay\nPROXIPLAY SASU, 214 boulevard de la République François Mitterrand, 59240 Dunkerque\n" +
  "SIRET 988 968 376 00018 · contact@proxiplay.fr · 07 59 60 69 86";

function euros(cents) {
  return new Intl.NumberFormat("fr-FR", {style: "currency", currency: "EUR"}).format((cents || 0) / 100)
    .replace(/ | /g, " ");
}

function parisDate(ms, withTime = false) {
  if (!ms) return "";
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris", day: "2-digit", month: "2-digit", year: "numeric",
    ...(withTime ? {hour: "2-digit", minute: "2-digit"} : {}),
  }).format(new Date(ms));
}

function originLabel(type) {
  return type === "demarchee" ? "démarchée (art. 4.2)" : "spontanée (art. 4.2)";
}

function enseigneLabel(contract) {
  const request = contract.enseigne_request;
  const name = contract.enseigne_name || request?.name || "";
  return request && !contract.enseigne_id ?
    `${name} (${request.address}, ${request.postal_code} ${request.city})` : name;
}

function recapLines(contract) {
  const offer = contract.offer || {};
  const lines = [
    `Enseigne : ${enseigneLabel(contract)}`,
    `Entreprise : ${contract.raison_sociale} · SIRET ${contract.siret}`,
    `Offre : ${offer.label} (abonnement annuel, une enseigne)`,
    `Prix de la première année : ${euros(offer.first_year_ht_cents)} HT, TVA 20 % ${euros(offer.first_year_ttc_cents - offer.first_year_ht_cents)}, ` +
      `soit ${euros(offer.first_year_ttc_cents)} TTC`,
  ];
  if (offer.discount_ht_cents > 0) {
    lines.push(`Remise de première année (code ${contract.promo?.code || "—"}) : ${euros(offer.discount_ht_cents)} HT`);
  }
  lines.push(
    `Prix du renouvellement : ${euros(offer.renewal_ht_cents)} HT, soit ${euros(offer.renewal_ttc_cents)} TTC par an`,
    "Durée : douze mois à compter de la date d'activation, renouvelable (art. 9)",
    `Origine de la souscription : ${originLabel(contract.origin?.type)}`,
    `Conditions générales de vente acceptées : version ${contract.cgv?.version || ""}`,
  );
  return lines.map((line) => `- ${line}`).join("\n");
}

function requestAcknowledgement(contract) {
  return {
    to: contract.owner_email,
    subject: "ProxiPlay : nous avons bien reçu votre demande de souscription",
    text: [
      "Bonjour,",
      "",
      "Nous avons bien reçu votre demande de souscription. Ce message n'est pas une confirmation : " +
        "le contrat n'est conclu qu'à l'envoi de la confirmation de souscription, après vérification de votre demande, " +
        "dans un délai maximal de deux jours ouvrés (CGV, art. 4.1). Aucune somme n'est encaissée avant cette confirmation.",
      "",
      "Votre demande :",
      recapLines(contract),
      "",
      kSignature,
    ].join("\n"),
  };
}

function adminNewRequest(contract, contractId) {
  return {
    to: contract.admin_alert_email,
    subject: `[ProxiPlay] Nouvelle demande de souscription à vérifier : ${enseigneLabel(contract)}`,
    text: [
      "Nouvelle demande de souscription, à confirmer ou refuser dans les deux jours ouvrés (CGV, art. 4.1).",
      "",
      `Demande : ${contractId}`,
      `Compte : ${contract.owner_email}`,
      recapLines(contract),
      "",
      `Console : ${kConsoleUrl}`,
    ].join("\n"),
  };
}

function visitReportAcknowledgement(contract) {
  return {
    to: contract.owner_email,
    subject: "ProxiPlay : signalement de la visite d'un représentant enregistré",
    text: [
      "Bonjour,",
      "",
      `Nous avons enregistré votre signalement de la visite d'un représentant de PROXIPLAY pour l'enseigne ${enseigneLabel(contract)}. ` +
        "Votre souscription est désormais traitée comme démarchée (CGV, art. 4.2) : l'article 7 s'applique, et les sommes déjà versées " +
        "sont remboursées en cas de rétractation.",
      "",
      "Pour une souscription démarchée, aucun paiement ni renseignement de carte bancaire n'est demandé avant l'expiration du délai " +
        "de rétractation de quatorze jours, qui court à compter du lendemain de la conclusion du contrat (art. 4.2, 7.2 et 7.4).",
      "",
      `Pour vous rétracter, adressez une déclaration non équivoque à ${kContactEmail} ou par courrier à ${kPostalAddress} (art. 7.3).`,
      "",
      kSignature,
    ].join("\n"),
  };
}

function adminVisitReport(contract, contractId) {
  return {
    to: contract.admin_alert_email,
    subject: `[ProxiPlay] Visite signalée par le commerçant : ${enseigneLabel(contract)}`,
    text: [
      "Le commerçant a signalé la visite d'un représentant (art. 4.2). La souscription est désormais démarchée.",
      "",
      `Demande : ${contractId} (état : ${contract.state})`,
      `Compte : ${contract.owner_email}`,
      "",
      `Console : ${kConsoleUrl}`,
    ].join("\n"),
  };
}

function refusalNotice(contract, motifLabel) {
  const detail = contract.public_refusal?.detail;
  return {
    to: contract.owner_email,
    subject: "ProxiPlay : votre demande de souscription n'a pas pu être acceptée",
    text: [
      "Bonjour,",
      "",
      `Après vérification, nous ne pouvons pas donner suite à votre demande de souscription pour l'enseigne ${enseigneLabel(contract)}.`,
      "",
      `Motif (CGV, art. 4.1) : ${motifLabel}${detail ? ` — ${detail}` : ""}.`,
      "",
      "Aucun contrat n'a été conclu et aucune somme n'a été encaissée. " +
        `Pour toute question, vous pouvez nous écrire à ${kContactEmail}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

function adminPendingAlert(contract, contractId, {level, submittedMs, deadlineMs}) {
  const priority = level === "priority";
  return {
    to: contract.admin_alert_email,
    subject: `${priority ? "[ProxiPlay][PRIORITAIRE] Délai de deux jours ouvrés dépassé" : "[ProxiPlay] Demande en attente depuis un jour ouvré"} : ${enseigneLabel(contract)}`,
    text: [
      priority ?
        "La demande ci-dessous n'a été ni confirmée ni refusée dans le délai maximal de deux jours ouvrés (CGV, art. 4.1)." :
        "La demande ci-dessous attend une décision depuis un jour ouvré. Le délai maximal de l'art. 4.1 est de deux jours ouvrés.",
      "Aucune validation tacite ni refus automatique : la décision reste manuelle.",
      "",
      `Demande : ${contractId}`,
      `Reçue le : ${parisDate(submittedMs, true)}`,
      `Délai de deux jours ouvrés : ${parisDate(deadlineMs, true)}`,
      `Compte : ${contract.owner_email}`,
      "",
      `Console : ${kConsoleUrl}`,
    ].join("\n"),
  };
}

// Formulaire de retractation (annexe des CGV V2.1), reproduit dans la
// confirmation d'une souscription demarchee (art. 4.3).
const kWithdrawalForm = [
  "FORMULAIRE DE RÉTRACTATION",
  "(À compléter et renvoyer uniquement si vous souhaitez vous rétracter.)",
  "",
  `À l'attention de ${kPostalAddress}, ${kContactEmail}.`,
  "",
  "Je/nous (1) vous notifie/notifions (1) par la présente ma/notre (1) rétractation du contrat portant sur la fourniture " +
    "du service suivant : abonnement PROXIPLAY, offre [Autonome / Accompagnée] (1).",
  "Contrat conclu le (date de la confirmation de souscription) : …………",
  "Nom du Partenaire / de l'entreprise et enseigne concernée : …………",
  "SIRET : ………… Adresse : ………… Adresse e-mail du compte : …………",
  "Date : ………… Signature (uniquement en cas de notification sur papier) : …………",
  "(1) Rayer la mention inutile.",
].join("\n");

/**
 * Confirmation de souscription (art. 4.3) : support durable. Date de
 * conclusion, recapitulatif, CGV jointes (version et empreinte) ; pour une
 * souscription demarchee, informations et formulaire de retractation.
 */
function confirmationNotice(contract, contractId, {conclusionMs, deadlineMs, cgv}) {
  const demarchee = contract.origin?.type === "demarchee";
  const lines = [
    "Bonjour,",
    "",
    `Nous confirmons votre souscription. Le contrat est conclu à la date d'envoi de ce message : le ${parisDate(conclusionMs, true)} ` +
      "(heure de Paris, CGV, art. 4.1).",
    "",
    "Récapitulatif contractuel :",
    recapLines({...contract, cgv: {version: cgv.version}}),
    `- Référence : ${contractId}`,
    "",
    `Conditions générales de vente acceptées : version ${cgv.version}, jointes à ce message en PDF ` +
      `(empreinte SHA-256 : ${cgv.sha256}).`,
    "",
    "Paiement et activation : aucune somme n'a été encaissée à ce jour. Le premier paiement est demandé par une invitation à payer, " +
      "valable quinze jours (art. 8.1). Le service est activé après confirmation du paiement ; la période annuelle commence " +
      "à la date d'activation (art. 8.2).",
    "",
  ];
  if (demarchee) {
    lines.push(
      "Droit de rétractation (souscription démarchée, art. 7) : vous pouvez vous rétracter sans justifier votre décision " +
        `pendant quatorze jours à compter du lendemain de la conclusion du contrat, soit jusqu'au ${parisDate(deadlineMs)} inclus. ` +
        "Aucun paiement n'est demandé ni encaissé, et aucune carte bancaire ni autorisation de prélèvement ne vous est demandée, " +
        "pendant ce délai (art. 7.4). Aucune somme n'est due si vous vous rétractez avant son expiration (art. 7.5).",
      "",
      `Pour vous rétracter : toute déclaration non équivoque adressée à ${kContactEmail} ou par courrier à ${kPostalAddress}, ` +
        "ou le formulaire ci-dessous (art. 7.3).",
      "",
      kWithdrawalForm,
      "",
    );
  } else {
    lines.push(
      "Souscription spontanée (art. 4.2). Si vous avez reçu la visite d'un représentant de PROXIPLAY sans que votre souscription " +
        `ait été enregistrée comme démarchée, vous pouvez le signaler jusqu'au ${parisDate(deadlineMs)} inclus, ` +
        `depuis votre espace commerçant ou à ${kContactEmail} : elle sera alors traitée comme démarchée et l'article 7 s'appliquera.`,
      "",
    );
  }
  lines.push(kSignature);
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : confirmation de votre souscription (${enseigneLabel(contract)})`,
    text: lines.join("\n"),
  };
}

// ---- Tranche 2a

/** Invitation a payer (art. 8.1) : lien ProxiPlay personnel, valable 15 jours. */
function paymentInvitation(contract, contractId, {url, expiresMs}) {
  const offer = contract.offer || {};
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : invitation à régler votre abonnement (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Votre souscription pour l'enseigne ${enseigneLabel(contract)} est conclue. Vous pouvez régler la première année ` +
        `(${euros(offer.first_year_ttc_cents)} TTC, soit ${euros(offer.first_year_ht_cents)} HT) sur la page sécurisée suivante, ` +
        "après connexion à votre espace commerçant :",
      "",
      url,
      "",
      `Ce lien est personnel et valable jusqu'au ${parisDate(expiresMs)} inclus (quinze jours, CGV art. 8.1). ` +
        "Sans paiement dans ce délai, la souscription non activée peut être close après un rappel, sans rien facturer.",
      "Le service est activé après confirmation du paiement ; la période annuelle commence à cette date (art. 8.2).",
      "",
      "Le paiement est traité par Stripe ; ProxiPlay ne conserve pas les numéros de carte.",
      "",
      kSignature,
    ].join("\n"),
  };
}

module.exports = {
  paymentInvitation,
  kWithdrawalForm,
  confirmationNotice,
  adminPendingAlert,
  refusalNotice,
  visitReportAcknowledgement,
  adminVisitReport,
  kContactEmail,
  kPostalAddress,
  kSignature,
  kConsoleUrl,
  euros,
  parisDate,
  originLabel,
  enseigneLabel,
  recapLines,
  requestAcknowledgement,
  adminNewRequest,
};
