# Notification Schema

## But

Le collection Firestore `ff_push_notifications` sert de file d'attente pour les push envoyées par le backend.

Le consommateur principal lit ce schéma dans `firebase/functions/index.js`, notamment dans `sendPushNotifications()`.

## Source de verite

Les payloads doivent etre construits via:

- `buildPushNotificationRequestData()` dans `firebase/functions/index.js`
- `queuePushNotificationRequest()` dans `firebase/functions/push_notification_request.js`

Ne pas recreer le schema a la main si ce n'est pas necessaire.

## Champs attendus

Champs utilises par le pipeline:

- `notification_title`: titre du push
- `notification_text`: corps du push
- `notification_image_url`: URL image ou `""`
- `notification_sound`: son ou `""`
- `parameter_data`: donnees additionnelles, souvent `""`
- `initial_page_name`: page cible, souvent `""`
- `target_audience`: audience/device type, souvent `"All"`
- `target_user_group`: groupe cible, souvent `"All"`
- `user_refs`: chemin Firestore utilisateur, ou liste jointe par virgules selon le flux admin
- `status`: doit etre `"started"` a la creation
- `created_at`: `serverTimestamp()`
- `created_by`: identifiant technique ou chemin utilisateur

## Format de `user_refs`

Formats actuellement supportes par le backend:

- `users/<uid>`
- `users/<uid1>,users/<uid2>,...`

Pour les fonctions custom, preferer un seul chemin utilisateur par document.

Ne pas ecrire:

- un tableau de `DocumentReference`
- un tableau de strings
- un champ `user_refs` vide si la notification cible des utilisateurs precis

## Champs a ne pas utiliser a la place

Ces noms ne sont pas le contrat du pipeline:

- `title`
- `message`
- `timestamp`

Ils peuvent sembler naturels, mais `sendPushNotifications()` lit `notification_title` et `notification_text`.

## Producteurs actuels

Cote `firebase/functions/index.js`:

- `queueUserScopedPushNotification()`
- `queuePrizePushNotification()`
- `createAdminPushNotification()`
- notifications "nouveau jeu disponible"
- notifications "relance inactifs"

Cote `firebase/functions` (autres fichiers du meme codebase):

- `participate_in_game_transaction.js`
- `draw_animation_winner.js`

`deleteEnseigneAndGames` et `deleteCommercantAccount` vivent aussi dans
`firebase/functions` (migrees depuis l'ancien codebase separe
`firebase/custom_cloud_functions`, retire) — aucun producteur de
notification.

## Regle pratique

Si un nouveau flux doit pousser une notification:

1. construire le document via le helper partage du dossier concerne
2. ecrire `status: "started"`
3. fournir un `created_by` explicite
4. garder `user_refs` au format chemin Firestore

## Incident deja rencontre

Une ancienne implementation ecrivait `title` / `message` et un tableau dans `user_refs`.
Resultat: le pipeline central pouvait ignorer la notification ou ne pas resoudre correctement les destinataires.
