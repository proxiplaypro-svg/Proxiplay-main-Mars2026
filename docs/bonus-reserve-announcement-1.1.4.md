# Annonce de la réserve de parties bonus (ProxiPlay 1.1.4)

Document du 10/11/2026, mis à jour avec les décisions du même jour. Rien n'a
été envoyé ni déployé. Les règles de jeu, les soldes et le fonctionnement de
la réserve `bonus_part` ne changent pas.

## 1. Affichage actuel du solde

| Endroit | Ce qui s'affiche |
|---|---|
| Barre du haut | « N chances » = parties du jour, puis « +N bonus » en dessous s'il y en a. La pastille passe au rouge quand le total jouable est de 1 ou moins. |
| Accueil | Pas de compteur dédié. La bannière « plus de chances » se base sur le total jouable, jour + bonus. |
| Profil | Carte « Mes parties » : parties du jour, parties bonus et la phrase « conservées jusqu'à ce que vous les jouiez ». |
| Détail d'un jeu | Le blocage « plus de parties » ne s'applique que sans partie du jour ni bonus. |

Les versions 1.1.3 et antérieures n'affichent que les parties du jour.

## 2. Annonce dans l'app (conservée telle quelle)

- Titre « Vos parties bonus restent à vous ! 🎉 », le texte validé, et le
  bouton « Compris ! ».
- Elle s'adresse aux joueurs connectés : ni invités, ni commerçants, ni
  administrateurs. Elle s'affiche sur l'accueil.
- Elle est mémorisée localement, par compte : la clé
  `bonus_reserve_announcement_1_1_4_seen/<uid>` est enregistrée au moment de
  l'affichage.

| Situation | Résultat |
|---|---|
| Réouverture de l'app, même compte | Pas réaffichée |
| Déconnexion, puis reconnexion du même compte | Pas réaffichée |
| Autre compte sur le même appareil | Affichée une fois pour ce compte |
| Nouvel appareil ou réinstallation | Affichée une nouvelle fois (limite du stockage local) |

Rien n'est écrit dans Firestore.

## 3. Rappel quotidien de 18:00 (`remindUsersWithRemainingDailyPlays`)

Les 8 textes tirés au hasard sont remplacés par un message unique :

- **Titre** : « Il vous reste des parties du jour ! »
- **Texte** : « Jouez-les avant minuit. Vos parties bonus, elles, sont
  conservées. »

**Destinataires.** Seuls les comptes qui ont encore des parties du jour
(`remaining_part > 0`) reçoivent le rappel. La requête faisait déjà ce
filtre, et une vérification par compte le confirme. Un joueur qui n'a plus
que des parties bonus ne reçoit rien. Les commerçants et les administrateurs
sont désormais exclus.

**Envoi.** Un document par joueur et par jour
(`daily_remaining_plays_<date>_<uid>`), comme avant. L'interrupteur
`app_config/notifications.dailyRemainingChancesReminderEnabled` reste la
seule commande de l'envoi.

À déployer : la fonction `remindUsersWithRemainingDailyPlays`, compilée dans
`lib/share_promo/daily_plays_reminder.js`.

## 4. Notification push d'information sur le service (préparée, pas envoyée)

- **Titre** : « 🎁 Vos parties bonus ne disparaissent plus ! »
- **Message** : « Conservez vos parties bonus et utilisez-les quand vous
  voulez. Mettez ProxiPlay à jour pour en profiter ! »
- **Appui** : il ouvre l'accueil joueur.
- **Nature** : une information sur l'évolution du service, sans offre
  commerciale.
  - Le consentement marketing ne s'y applique pas. Dans le code, il ne
    couvre que les e-mails commerciaux (`lib/marketing_consent_recipients.js`,
    « Service messages intentionally do not import this module »).
  - Ce classement reste une décision métier. Si la notification devenait
    promotionnelle, il faudrait la réserver aux joueurs ayant donné leur
    consentement.

### Qui la reçoit : toutes les conditions doivent être remplies

1. **Autorisation des notifications sur le téléphone.** Il n'existe pas de
   préférence push dans l'app : le jeton FCM n'est enregistré que si le
   joueur a accepté les notifications sur son téléphone.
   - Le jeton est retiré à la déconnexion et à la suppression du compte.
   - Un jeton invalide est nettoyé à l'envoi.
   - Si l'autorisation est retirée ensuite dans les réglages du téléphone,
     c'est le téléphone qui n'affiche pas la notification.
2. **Profil `users/{uid}` de rôle `joueur`.** Le rôle est lu dans le
   profil, jamais dans le document du jeton.
3. **Compte actif.** Il n'est ni supprimé (`deleted`, `auto_deleted`), ni
   suspendu ou refusé (`account_status`, `player_status_cached`).
4. **Téléphone non partagé avec un autre type de compte.** Un jeton porté
   par plusieurs comptes n'est retenu que si tous sont des joueurs
   éligibles. Un téléphone partagé avec un commerçant ou un administrateur
   est exclu.

Un compte sans rôle (62 le 10/11) ne reçoit rien. Le code est dans
`push_target_groups.js` et dans le groupe `Players` de `sendPushNotifications`.

### Un seul envoi possible

Le document a un identifiant fixe :
`ff_push_notifications/announcement_bonus_reserve_1_1_4`. Il est créé avec
`create()`, qui échoue s'il existe déjà. Aucun déclencheur ni tâche
planifiée ne l'envoie, et un test le vérifie.

### Conditions d'envoi

> ⚠️ **`sendPushNotificationsTrigger` doit être déployée avant tout envoi.**
> C'est vérifié dans le code : la version en production, celle de `main` et
> celle de `Proxiplay-develop` traitent toutes un groupe inconnu comme
> « tous » (`: true`). Sans ce déploiement préalable, la notification
> partirait aussi aux commerçants et aux administrateurs.

1. L'app 1.1.4 est publiée et disponible sur les **deux** stores.
2. Les Functions de la réserve bonus sont déployées : sans elles, la
   notification annoncerait un fonctionnement absent du serveur.
3. `sendPushNotificationsTrigger` 1.1.4 est déployée. Le contrôler en
   lecture seule avec
   `gcloud functions describe sendPushNotificationsTrigger --region us-central1 --project proxi-play-odzp2e`
   (date `updateTime`).
4. Simulation, sans rien écrire :
   `node scripts/queue_bonus_reserve_announcement.js`
5. Envoi, une seule fois :

   ```
   node scripts/queue_bonus_reserve_announcement.js --apply --confirm \
     --project=proxi-play-odzp2e --players-group-deployed --created-by=users/<uid admin>
   ```

   Le script refuse de s'exécuter sans ces options.

## 5. Anciens messages vérifiés

| Message | État |
|---|---|
| 10e participation | « … 3 parties bonus ! Elles sont conservées jusqu'à ce que vous les jouiez. » |
| Anniversaire, texte par défaut | « … 3 parties bonus, conservées jusqu'à ce que vous les jouiez ! 🎁 » |
| Anniversaire, ancien texte configuré en production | Remplacé à l'envoi par le texte par défaut (testé) |
| « Tous les jeux jusqu'à minuit » | Accès parrainage, règle distincte, exact |
| Rappel de 18:00 | Corrigé (section 3) |
