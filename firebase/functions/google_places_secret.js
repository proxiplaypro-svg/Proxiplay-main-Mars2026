// Secret Manager unique partage par toutes les integrations Google Places
// de ce projet (recherche d'etablissement + recuperation de note/avis).
// Une seule declaration defineSecret() ici, importee partout ailleurs,
// pour eviter toute ambiguite sur "combien de secrets GOOGLE_PLACES_API_KEY
// existent" -- il n'y en a qu'un.
//
//   firebase functions:secrets:set GOOGLE_PLACES_API_KEY

const {defineSecret} = require("firebase-functions/params");

const googlePlacesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");

module.exports = {googlePlacesApiKey};
