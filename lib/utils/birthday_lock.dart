/// Date de naissance verrouillee (1.1.4).
///
/// Le joueur la saisit une fois ; une fois enregistree, elle reste visible
/// mais n'est plus modifiable depuis l'app. Les regles Firestore refusent de
/// toute facon une autre valeur, et seule la callable Admin
/// adminCorrectPlayerBirthday peut la corriger (motif journalise).
library;

const String kBirthdayLockedHelpText =
    'Date de naissance enregistrée. Une erreur ? Contactez le support '
    '(contact@proxiplay.fr) pour la faire corriger.';

const String kBirthdayConfirmTitle = 'Confirmer votre date de naissance';

String birthdayConfirmMessage(String formattedDate) =>
    'Vous êtes né(e) le $formattedDate ?\n\n'
    'Une fois enregistrée, votre date de naissance ne pourra plus être '
    'modifiée depuis l’application. En cas d’erreur, seul le support pourra '
    'la corriger.';

/// Une date deja enregistree verrouille le champ.
bool isBirthdayLocked(DateTime? storedBirthday) => storedBirthday != null;

/// Valeur a envoyer avec le profil : jamais pour un commercant, jamais une
/// fois la date enregistree (le champ reste alors intact cote Firestore, le
/// set(merge) n'ecrivant pas les valeurs nulles), sinon la date choisie.
DateTime? birthdayToSubmit({
  required bool isMerchant,
  required DateTime? storedBirthday,
  required DateTime? pickedBirthday,
}) {
  if (isMerchant || isBirthdayLocked(storedBirthday)) {
    return null;
  }
  return pickedBirthday;
}

/// La confirmation n'est demandee qu'a la premiere saisie d'un joueur.
bool shouldConfirmBirthdayBeforeSave({
  required bool isMerchant,
  required DateTime? storedBirthday,
  required DateTime? pickedBirthday,
}) =>
    !isMerchant && !isBirthdayLocked(storedBirthday) && pickedBirthday != null;
