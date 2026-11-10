# Annonce de la réserve de parties bonus (ProxiPlay 1.1.4)

Document du 10/11/2026. Rien n'a été envoyé ni déployé. Les règles de jeu et
le fonctionnement de la réserve `bonus_part` ne changent pas.

## 1. Affichage actuel du solde

| Endroit | Ce qui s'affiche |
|---|---|
| Barre du haut (`app_bar_joueur_widget.dart`) | « N chances » = parties du jour, puis « +N bonus » en dessous s'il y en a. La pastille passe au rouge quand le total jouable (jour + bonus) est de 1 ou moins. |
| Accueil | Pas de compteur dédié. La bannière « plus de chances » se base sur le total jouable, jour + bonus. |
| Profil | Carte « Mes parties » : « N parties du jour · N parties bonus » et l'explication « Vos parties bonus sont conservées jusqu'à ce que vous les jouiez… ». |
| Détail d'un jeu | Le blocage « plus de parties » ne s'applique que sans partie du jour ni bonus (`hasNoPlayableParts`). |

Les versions 1.1.3 et antérieures affichent seulement les parties du jour. Le
serveur utilise quand même la réserve bonus pour ces joueurs : c'est la raison
de la phrase « Mettez ProxiPlay à jour » dans la notification.

## 2. Annonce dans l'app

- **Titre** : « Vos parties bonus restent à vous ! 🎉 »
- **Texte** : « Bonne nouvelle ! Les parties bonus gagnées sur ProxiPlay sont
  désormais conservées, même après minuit. Cumulez-les et utilisez-les quand
  vous voulez, en plus de vos 3 parties quotidiennes. »
- **Bouton** : « Compris ! »

Fichiers : `lib/utils/bonus_reserve_announcement.dart`,
`lib/components/bonus_reserve_announcement_dialog.dart`, appel dans l'accueil
joueur (`_presentBonusReserveAnnouncement`).

**Qui la voit.** Les joueurs connectés. Elle n'est pas montrée aux invités,
aux comptes anonymes, aux commerçants ni aux administrateurs.

**Quand.** Sur l'accueil, environ 0,8 s après son ouverture. Si une autre
fenêtre est déjà ouverte à ce moment (félicitation de parrainage par
exemple), l'annonce n'est pas comptée comme vue. Elle apparaît à une
prochaine ouverture de l'accueil.

**Mémorisation locale** (`SharedPreferences`, clé
`bonus_reserve_announcement_1_1_4_seen/<uid>`), enregistrée au moment de
l'affichage :

| Situation | Résultat |
|---|---|
| Réouverture de l'app, même compte | Pas réaffichée |
| Déconnexion, puis reconnexion du même compte | Pas réaffichée : la déconnexion n'efface pas ce stockage |
| Déconnexion, puis connexion d'un autre compte sur le même appareil | Affichée une fois pour ce nouveau compte |
| Nouvel appareil, réinstallation, données de l'app effacées | Affichée une nouvelle fois : c'est la limite d'un stockage local |

Rien n'est écrit dans Firestore.

## 3. Notification push préparée, pas envoyée

- **Titre** : « 🎁 Vos parties bonus ne disparaissent plus ! »
- **Message** : « Conservez vos parties bonus et utilisez-les quand vous
  voulez. Mettez ProxiPlay à jour pour en profiter ! »
- **Appui** : ouvre l'accueil joueur, qui existe dans toutes les versions.
- **Cible** : le nouveau groupe `Players`, c'est-à-dire les comptes de rôle
  `joueur` seulement. Le groupe `NormalUsers` de l'Admin aurait aussi visé
  les commerçants.

**Envoi unique.** Le document a un identifiant fixe :
`ff_push_notifications/announcement_bonus_reserve_1_1_4`. Il est créé avec
`create()`, qui échoue s'il existe déjà, donc un second lancement ne
renvoie rien. Aucun déclencheur ni tâche planifiée ne l'envoie, et un test
le vérifie.

**Procédure, après publication sur les deux stores :**

1. Déployer d'abord `sendPushNotificationsTrigger` dans sa version 1.1.4,
   qui connaît le groupe `Players`.

   > ⚠️ **L'ordre est obligatoire.** La version en production traite un
   > groupe inconnu comme « tous » : sans ce déploiement préalable, la
   > notification partirait aussi aux commerçants et aux administrateurs.

2. Simuler l'envoi, sans rien écrire :

   ```
   node scripts/queue_bonus_reserve_announcement.js
   ```

3. Envoyer :

   ```
   node scripts/queue_bonus_reserve_announcement.js --apply --confirm \
     --project=proxi-play-odzp2e --players-group-deployed --created-by=users/<uid admin>
   ```

   Le script refuse de s'exécuter sans ces trois options.

## 4. Anciens messages vérifiés

| Message | État |
|---|---|
| 10e participation (`play_balance.js`) | « Vous avez gagné 3 parties bonus ! Elles sont conservées jusqu'à ce que vous les jouiez. » Correct. |
| Anniversaire, texte par défaut (`constants.js`) | « … 3 parties bonus, conservées jusqu'à ce que vous les jouiez ! 🎁 » Correct. |
| Anniversaire, texte configuré en production | L'ancien texte « Profitez de vos avantages du jour… » est remplacé à l'envoi par le texte par défaut. Testé. |
| « Tous les jeux jusqu'à minuit » (parrainage) | Inchangé. C'est l'accès parrainage, qui reste une règle distincte et dure bien jusqu'à minuit. |
| « Vous avez déjà joué aujourd'hui » et « Revenez demain » (page de jeu) | Ils portent sur la limite par jeu et par jour, ou sur l'absence de toute partie. Corrects. |

## 5. À décider (non modifié)

1. **Rappel quotidien** (`daily_plays_reminder`). Les textes « Ne laissez
   pas vos parties expirer » et « Utilisez vos chances avant la fin de la
   journée » parlent des parties du jour et restent exacts. Un joueur qui a
   des bonus pourrait pourtant croire qu'ils expirent aussi. Faut-il écrire
   « parties du jour » dans ces textes ?
2. **Consentement marketing.** Faut-il réserver ce push aux joueurs qui ont
   donné leur consentement marketing ? Le message est une information sur
   le service, mais il incite à mettre l'app à jour. C'est une décision
   juridique et métier : en l'état, le push suit seulement l'autorisation
   de notifications du téléphone, comme les autres push de l'Admin.
