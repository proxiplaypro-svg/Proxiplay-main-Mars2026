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

/** Activation (art. 8.2) : date d'activation communiquee, debut de la periode annuelle. */
function activationNotice(contract, contractId, {activatedMs, periodEndMs}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : paiement confirmé, votre abonnement est actif (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Nous avons reçu la confirmation de votre paiement. Votre abonnement ${contract.offer?.label || ""} pour l'enseigne ` +
        `${enseigneLabel(contract)} est activé le ${parisDate(activatedMs)} : c'est le point de départ de la période annuelle (CGV, art. 8.2).`,
      periodEndMs ? `Échéance de cette période : ${parisDate(periodEndMs)}. Le renouvellement est automatique pour douze mois, ` +
        "désactivable depuis votre espace commerçant jusqu'à la date d'échéance incluse, tant que le prélèvement n'a pas eu lieu (art. 9)." : "",
      "",
      `Référence : ${contractId}. La facture est disponible dans votre espace commerçant.`,
      "",
      kSignature,
    ].filter((line) => line !== null).join("\n"),
  };
}

/** Paiement recu alors qu'aucun paiement n'etait attendu : rembourse (art. 8.1). */
function latePaymentRefundNotice(contract, contractId) {
  return {
    to: contract.owner_email,
    subject: "ProxiPlay : paiement remboursé",
    text: [
      "Bonjour,",
      "",
      `Nous avons reçu un paiement pour la souscription ${contractId} (enseigne ${enseigneLabel(contract)}) alors qu'elle n'attendait ` +
        "plus de paiement (souscription close, rétractation ou délai de rétractation en cours). Ce paiement ne réactive pas la " +
        "souscription : il vous est remboursé intégralement et l'abonnement correspondant est annulé (CGV, art. 8.1).",
      "",
      `Pour souscrire de nouveau, vous pouvez déposer une nouvelle demande depuis votre espace commerçant ou nous écrire à ${kContactEmail}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/** Echec de prelevement d'un renouvellement (art. 11) : notification sans delai. */
function renewalFailedNotice(contract, contractId, {graceUntilMs, invoiceUrl}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : le prélèvement de votre renouvellement a échoué (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Le prélèvement du renouvellement de votre abonnement pour l'enseigne ${enseigneLabel(contract)} n'a pas abouti.`,
      graceUntilMs ? `Vous disposez d'un délai de régularisation de quinze jours, jusqu'au ${parisDate(graceUntilMs)} inclus, ` +
        "pendant lequel vos accès sont maintenus (CGV, art. 11)." : "Vous disposez d'un délai de régularisation de quinze jours (CGV, art. 11).",
      invoiceUrl ? `Pour régulariser : ${invoiceUrl}` : "Pour régulariser, mettez à jour votre moyen de paiement depuis votre espace commerçant.",
      "",
      "Si vous ne souhaitez pas renouveler, vous pouvez désactiver le renouvellement pendant ce délai : l'abonnement prend fin, " +
        "la facture du renouvellement est annulée et aucune pénalité n'est réclamée (art. 9).",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

// --- Lot 1.9 : taches planifiees ---------------------------------------------

/** Rappel de paiement (art. 8.1 : la cloture n'intervient qu'apres un rappel). */
function paymentReminder(contract, contractId, {url, expiresMs}) {
  const offer = contract.offer || {};
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : rappel, votre abonnement n'est pas encore réglé (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Votre souscription pour l'enseigne ${enseigneLabel(contract)} attend toujours le règlement de la première année ` +
        `(${euros(offer.first_year_ttc_cents)} TTC, soit ${euros(offer.first_year_ht_cents)} HT).`,
      "Vous pouvez la régler sur la page sécurisée suivante, après connexion à votre espace commerçant :",
      "",
      url,
      "",
      `Ce lien remplace le précédent et reste valable jusqu'au ${parisDate(expiresMs)} inclus (CGV art. 8.1). ` +
        "Sans paiement à cette date, la souscription non activée sera close, sans rien facturer.",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/** Cloture sans paiement (art. 8.1) : rien n'est facture. */
function closureNotice(contract, contractId, {expiresMs}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : souscription close sans paiement (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Le lien de paiement de votre souscription pour l'enseigne ${enseigneLabel(contract)} a expiré le ${parisDate(expiresMs)} ` +
        "sans règlement, malgré notre rappel. La souscription non activée est close : rien n'est facturé (CGV art. 8.1).",
      "Un paiement reçu après cette clôture ne la réactiverait pas et serait remboursé. Pour souscrire à nouveau, " +
        "faites une nouvelle demande depuis votre espace commerçant.",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/**
 * Rappel avant l'echeance. 45 jours : rappel de l'art. 9 (date, montant TTC,
 * procedure de desactivation). 15 jours : second rappel, de courtoisie.
 */
function renewalReminder(contract, contractId, {renewalMs, amountTtcCents, amountHtCents, days}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : renouvellement de votre abonnement le ${parisDate(renewalMs)} (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Votre abonnement ${contract.offer?.label || ""} pour l'enseigne ${enseigneLabel(contract)} sera renouvelé automatiquement ` +
        `pour douze mois le ${parisDate(renewalMs)}.`,
      `Montant prévu : ${euros(amountTtcCents)} TTC (${euros(amountHtCents)} HT), prélevé au moyen du paiement enregistré.`,
      "",
      "Si vous ne souhaitez pas renouveler : connectez-vous à votre espace commerçant (https://www.proxiplay.fr/espace-commercant/) " +
        "et utilisez le bouton « Désactiver le renouvellement » de cette enseigne. C'est possible jusqu'à la date d'échéance incluse, " +
        "tant que le prélèvement du renouvellement n'a pas eu lieu. Vos prestations restent accessibles jusqu'à la fin de la période payée.",
      days === 45 ? "Ce rappel vous est adressé au moins quarante-cinq jours avant l'échéance (CGV art. 9)." : "",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].filter((line, i, all) => line !== "" || all[i - 1] !== "").join("\n"),
  };
}

/** Relance amiable pendant le delai de regularisation (art. 11). */
function graceReminder(contract, contractId, {day, graceUntilMs, invoiceUrl}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : relance, renouvellement impayé (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Le prélèvement du renouvellement de votre abonnement pour l'enseigne ${enseigneLabel(contract)} n'a toujours pas abouti` +
        (day > 0 ? ` (relance à ${day} jours).` : "."),
      graceUntilMs ? `Votre délai de régularisation court jusqu'au ${parisDate(graceUntilMs)} inclus ; vos accès sont maintenus ` +
        "jusque-là (CGV art. 11)." : "Vous disposez d'un délai de régularisation de quinze jours (CGV art. 11).",
      invoiceUrl ? `Pour régulariser : ${invoiceUrl}` : "Pour régulariser, mettez à jour votre moyen de paiement depuis votre espace commerçant.",
      "En cas de régularisation dans ce délai, aucune pénalité n'est réclamée (art. 8.5).",
      "",
      "Si vous ne souhaitez pas renouveler, vous pouvez désactiver le renouvellement pendant ce délai : l'abonnement prend fin, " +
        "la facture du renouvellement est annulée et aucune pénalité n'est réclamée (art. 9).",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/** Fin du delai de regularisation sans paiement (art. 11 : suspension possible, notifiee). */
function graceEndedNotice(contract, contractId, {graceUntilMs, invoiceUrl}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : délai de régularisation expiré (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Le délai de régularisation du renouvellement de votre abonnement pour l'enseigne ${enseigneLabel(contract)} a expiré ` +
        `le ${parisDate(graceUntilMs)} sans paiement.`,
      "Conformément à l'article 11 des CGV, ProxiPlay peut désormais suspendre la création de nouvelles opérations et, " +
        "si nécessaire, l'accès aux fonctionnalités payantes. Les droits des joueurs ayant déjà obtenu des gains sont préservés.",
      invoiceUrl ? `Pour régulariser : ${invoiceUrl}` : "Pour régulariser, mettez à jour votre moyen de paiement depuis votre espace commerçant.",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

// --- Lot 1.12 : fins de contrat ------------------------------------------------

/** Art. 9 : confirmation de la desactivation, fin a l'echeance. */
function renewalDisabledNotice(contract, contractId, {periodEndMs}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : renouvellement désactivé (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Nous confirmons la désactivation du renouvellement automatique de votre abonnement pour l'enseigne ${enseigneLabel(contract)} ` +
        "(CGV art. 9).",
      `Votre abonnement n'est pas renouvelé : il prend fin le ${parisDate(periodEndMs)}. Vos prestations restent accessibles ` +
        "jusqu'à cette date, fin de la période déjà payée. Aucun renouvellement ne sera facturé.",
      "La période en cours n'est pas remboursée (art. 10).",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/** Art. 9 : desactivation a l'echeance (avant prelevement) ou pendant le delai de regularisation. */
function renewalStoppedNotice(contract, contractId, {duringGrace, refundedCents}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : renouvellement désactivé, abonnement terminé (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Nous confirmons la désactivation du renouvellement de votre abonnement pour l'enseigne ${enseigneLabel(contract)} (CGV art. 9).`,
      duringGrace ?
        "Le prélèvement du renouvellement avait échoué : l'abonnement prend fin, la facture du renouvellement est annulée et aucune pénalité n'est réclamée." :
        "Votre période annuelle était arrivée à échéance : l'abonnement prend fin et la facture du renouvellement est annulée.",
      refundedCents > 0 ? `Le prélèvement du renouvellement, intervenu au moment de votre demande, vous est remboursé intégralement ` +
        `(${euros(refundedCents)}) ; le délai de crédit dépend de votre banque.` : "Aucune somme n'est prélevée pour le renouvellement.",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

/** Art. 9 : rappel des 45 jours non envoye, renouvellement annule et rembourse. */
function renewalRefundNotice(contract, contractId, {refundedCents}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : renouvellement annulé et remboursé (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Comme vous l'avez demandé, le renouvellement de votre abonnement pour l'enseigne ${enseigneLabel(contract)} est annulé ` +
        `et la somme prélevée (${euros(refundedCents)}) vous est remboursée intégralement : le rappel prévu quarante-cinq jours ` +
        "avant l'échéance ne vous avait pas été envoyé (CGV art. 9). L'abonnement prend fin aujourd'hui.",
      "Le délai de crédit dépend de votre banque.",
      "",
      `Référence : ${contractId}.`,
      "",
      kSignature,
    ].join("\n"),
  };
}

const kEndReasonTexts = Object.freeze({
  provider_breach: "à la suite d'un manquement de ProxiPlay (CGV art. 10)",
  unpaid_termination: "pour défaut de paiement, après mise en demeure restée sans effet (CGV art. 11)",
  breach: "pour manquement à vos obligations (CGV art. 18)",
  force_majeure: "pour un cas de force majeure ayant duré plus de soixante jours (CGV art. 23)",
});

/** Fins de contrat decidees par l'admin (art. 10, 11, 18, 23). */
function contractEndNotice(contract, contractId, {reason, refundedCents, endedMs}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : fin de votre abonnement (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Votre abonnement pour l'enseigne ${enseigneLabel(contract)} prend fin le ${parisDate(endedMs)}, ${kEndReasonTexts[reason]}.`,
      refundedCents > 0 ? `Un remboursement de ${euros(refundedCents)} vous est versé` +
        (reason === "force_majeure" ? " au prorata de la période non exécutée (art. 23)." : ".") :
        "Aucun remboursement n'est dû au titre de la période en cours.",
      reason === "unpaid_termination" ? "Les sommes restant dues demeurent exigibles (art. 11)." : "",
      "Les droits des joueurs ayant déjà obtenu des gains sont préservés.",
      "",
      `Référence : ${contractId}. Pour toute question : ${kContactEmail}.`,
      "",
      kSignature,
    ].filter((line, i, all) => line !== "" || all[i - 1] !== "").join("\n"),
  };
}

const kChannelLabels = {online: "fonction « Me rétracter » de votre espace commerçant", email: "e-mail", courrier: "courrier"};

/** Accuse de reception de la retractation (art. 7.3), sur support durable. */
function withdrawalAcknowledgement(contract, contractId, {sentMs, channel, refundedCents}) {
  return {
    to: contract.owner_email,
    subject: `ProxiPlay : accusé de réception de votre rétractation (${enseigneLabel(contract)})`,
    text: [
      "Bonjour,",
      "",
      `Nous accusons réception de votre rétractation du ${parisDate(sentMs, true)} (heure de Paris), reçue par ${kChannelLabels[channel] || channel}, ` +
        `pour la souscription ${contractId} (enseigne ${enseigneLabel(contract)}) (CGV, art. 7).`,
      "",
      refundedCents > 0 ?
        `La somme que vous aviez versée (${euros(refundedCents)}) vous est remboursée intégralement et l'abonnement est annulé.` :
        "Aucune somme n'est due (art. 7.5) et aucun paiement ne vous sera demandé.",
      "",
      kSignature,
    ].join("\n"),
  };
}

function adminWithdrawalNotice(contract, contractId, {channel, sentMs, refunds}) {
  return {
    to: contract.admin_alert_email,
    subject: `[ProxiPlay] Rétractation enregistrée : ${enseigneLabel(contract)}`,
    text: [
      `Rétractation du ${parisDate(sentMs, true)} par ${channel} pour la demande ${contractId}.`,
      refunds ? `${refunds} remboursement(s) effectué(s), abonnement annulé.` : "Aucun paiement à rembourser.",
      "",
      `Console : ${kConsoleUrl}`,
    ].join("\n"),
  };
}

module.exports = {
  paymentReminder,
  closureNotice,
  renewalReminder,
  graceReminder,
  graceEndedNotice,
  renewalDisabledNotice,
  renewalStoppedNotice,
  renewalRefundNotice,
  contractEndNotice,
  withdrawalAcknowledgement,
  adminWithdrawalNotice,
  activationNotice,
  latePaymentRefundNotice,
  renewalFailedNotice,
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
