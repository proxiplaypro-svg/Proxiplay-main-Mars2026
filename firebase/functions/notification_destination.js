// Resolution d'une destination structuree (destination_type/destination_id) vers
// le contrat push existant (initial_page_name/parameter_data), deja consomme
// cote Flutter par parametersBuilderMap dans
// lib/backend/push_notifications/push_notifications_handler.dart.
//
// Rien ici ne change le payload FCM ni sendPushNotifications() : cette
// resolution a lieu uniquement au moment de la creation du document
// ff_push_notifications (manuel ou automatique), avant ecriture -- la
// destination est donc deja figee pour une notification programmee.

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const kDestinationTypes = new Set([
  "game",
  "merchant",
  "internal",
  "external_url",
  "none",
]);

// Whitelist des ecrans internes autorises depuis l'Admin. Les noms de page
// doivent rester synchronises avec parametersBuilderMap (cote Flutter) --
// toutes ces entrees y sont deja presentes ou y sont ajoutees par ce meme
// chantier (ParrainageJoueurPage / ParrainageCommercantPage).
const kInternalDestinations = {
  home: "HomeJoueurPage",
  favoris: "FavorisJoueurPage",
  profil: "ProfilJoueurPage",
  gagnants: "LotsJoueurPage",
  parrainage_joueur: "ParrainageJoueurPage",
  parrainage_commercant: "ParrainageCommercantPage",
};

// Nom de page sentinelle, intercepte cote client avant tout pushNamed() --
// ce n'est pas une route go_router reelle, seulement un marqueur pour
// declencher l'ouverture d'une URL externe (voir push_notifications_handler.dart).
const kExternalUrlPageName = "ExternalUrlRedirectPage";

function throwInvalidDestination(message) {
  throw new functions.https.HttpsError("invalid-argument", message);
}

function isHttpsUrl(value) {
  if (typeof value !== "string" || !value.trim()) {
    return false;
  }
  try {
    const parsed = new URL(value.trim());
    return parsed.protocol === "https:";
  } catch (_) {
    return false;
  }
}

/**
 * Resout une destination envoyee par l'Admin (type + id) en
 * {initialPageName, parameterData} pret a etre passe a
 * buildPushNotificationRequestData(). Leve une HttpsError invalid-argument
 * si la destination est malformee, inconnue, ou pointe vers une ressource
 * qui n'existe pas.
 */
async function resolveNotificationDestination({destinationType, destinationId}) {
  const type = (destinationType || "none").toString().trim();
  const id = (destinationId || "").toString().trim();

  if (!kDestinationTypes.has(type)) {
    throwInvalidDestination(`destination_type invalide: ${type}`);
  }

  if (type === "none") {
    return {initialPageName: "", parameterData: ""};
  }

  if (type === "game") {
    if (!id) {
      throwInvalidDestination("destination_id (jeu) manquant.");
    }
    const gameSnap = await admin.firestore().collection("games").doc(id).get();
    if (!gameSnap.exists) {
      throwInvalidDestination("Le jeu selectionne n'existe pas.");
    }
    const enseigneRef = gameSnap.get("enseigne_id");
    return buildGameDestinationFromRefs({
      gameRef: gameSnap.ref,
      enseigneRef: enseigneRef && enseigneRef.path ? enseigneRef : null,
    });
  }

  if (type === "merchant") {
    if (!id) {
      throwInvalidDestination("destination_id (commerce) manquant.");
    }
    const enseigneSnap = await admin.firestore().collection("enseignes").doc(id).get();
    if (!enseigneSnap.exists) {
      throwInvalidDestination("Le commerce selectionne n'existe pas.");
    }
    return {
      initialPageName: "EnseigneDetailJoueurPage",
      parameterData: JSON.stringify({enseigneDoc: enseigneSnap.ref.path}),
    };
  }

  if (type === "internal") {
    if (!kInternalDestinations[id]) {
      throwInvalidDestination(`Ecran interne non autorise: ${id}`);
    }
    return buildInternalDestination(id);
  }

  // type === "external_url"
  if (!isHttpsUrl(id)) {
    throwInvalidDestination("L'URL de destination doit etre une URL https:// valide.");
  }
  return {
    initialPageName: kExternalUrlPageName,
    parameterData: JSON.stringify({url: id.trim()}),
  };
}

/**
 * Construit directement {initialPageName, parameterData} pour un jeu dont la
 * reference (et, si connue, celle de son enseigne) est deja en main -- evite
 * un aller-retour Firestore depuis les producteurs automatiques qui ont deja
 * charge le document du jeu (favori, J-3, etc.).
 */
function buildGameDestinationFromRefs({gameRef, enseigneRef}) {
  const parameterData = {
    gameDoc: gameRef.path,
    ...(enseigneRef && enseigneRef.path ? {enseigneDoc: enseigneRef.path} : {}),
  };
  return {
    initialPageName: "JeuDetailJoueurPage",
    parameterData: JSON.stringify(parameterData),
  };
}

/** Construit directement {initialPageName, parameterData} pour un ecran interne whitelists. */
function buildInternalDestination(key) {
  const pageName = kInternalDestinations[key];
  if (!pageName) {
    throw new Error(`Unknown internal destination key: ${key}`);
  }
  return {initialPageName: pageName, parameterData: ""};
}

module.exports = {
  kDestinationTypes,
  kInternalDestinations,
  kExternalUrlPageName,
  resolveNotificationDestination,
  buildGameDestinationFromRefs,
  buildInternalDestination,
  isHttpsUrl,
};
