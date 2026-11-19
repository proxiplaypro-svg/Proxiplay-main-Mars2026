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

module.exports = {
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
