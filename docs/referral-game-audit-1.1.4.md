# Jeu du parrainage — audit (ProxiPlay 1.1.4)

Audit du 10/11/2026, en lecture seule. Aucune modification de code ni de
données. Pour la production, j'ai lu uniquement des agrégats, les champs
non personnels des 2 jeux et le document de verrou.

## 1. Fonctionnement de bout en bout

1. **Création, dans l'Admin** (`/admin/parrainage/jeu`, API `referral-games`).
   Un jeu a un titre, un lot, des dates et le statut `draft`.
2. **Activation.**
   - Automatique : `autoManageReferralGames`, toutes les 15 minutes, passe
     en `active` le plus ancien brouillon dont la date de début est atteinte,
     sauf si un autre jeu est déjà actif.
   - Manuelle : bouton « Activer maintenant ».
   - Le verrou `app_config/referral_game_active`, tenu par
     `enforceSingleActiveReferralGame`, garantit qu'un seul jeu est actif.
3. **Ticket.** Quand un parrainage est validé, la création du compte filleul
   choisit le jeu qui couvre la date d'acceptation (`selectReferralGameForAcceptance`)
   et enregistre un événement durable dans `referral_reward_pending`, de mode
   `game` ou `classic`.
   - `processReferralReward` crée ensuite le ticket
     `referral_games/{id}/entries/{referralId}`.
   - En cas d'échec, `retryReferralRewards` réessaie toutes les 10 minutes.
   - Pendant un jeu, le parrain reçoit **un ticket seulement**, conformément
     à la décision du 23/10. Le drapeau `classic_and_game` existe mais aucun
     appelant ne l'utilise.
4. **Tirage.** `drawReferralGameWinner` tourne chaque nuit à minuit, ou
   « Tirer le gagnant » est lancé depuis l'Admin.
   - Le tirage attend tant qu'une récompense est en attente ou à vérifier.
   - Il exclut les comptes supprimés ou suspendus, crée le lot
     `prizes/referral_game_{id}` (remis par ProxiPlay) et le lien `my_lots`,
     puis passe le jeu en `ended`.
5. **Notification.** `notifyPrizeWon` envoie un e-mail et un push au
   gagnant. Le texte propre au parrainage est dans la 1.1.4 (`3106389`),
   pas encore déployé.
6. **App.** L'accueil affiche le jeu actif (requête limitée à 1). La page
   de détail affiche les tickets du joueur ; les règles Firestore ne lui
   laissent lire que les siens. Un message de confirmation s'affiche une
   seule fois après chaque nouveau ticket.

## 2. Production le 10/11

| Jeu | Statut | Période (heure de Paris) | Tickets | Tirage |
|---|---|---|---|---|
| `2MYxZBLZY4B9ml1QpLrB` | ended | 29/10 → 30/10 | 1 | terminé, 1 éligible |
| `SZgZkvzuTSkHSIjuJSO1` | active | 29/10 → 05/12 (tirage dans la nuit du 05/12) | 28 | — |

**Événements de récompense** : 38 au total, dont 29 en mode jeu (soit 28 + 1
tickets, cohérent) et 9 en mode classique. Aucun n'est en attente ni à
vérifier, et `pending_reward_count` vaut 0.

**Verrou** : il désigne `SZgZ…` depuis le 31/10 à 08:47 UTC. Le jeu de test
l'avait libéré le 29/10.

**Parrainages** : 206 acceptés et 1 615 en attente. Les invitations
n'expirent pas ; c'est connu et non modifié.

**Constat sur les dates.** `SZgZ…` affiche une date de début au 29/10, mais
il n'est devenu actif que le 31/10. Tant que le jeu de test était actif,
`autoManageReferralGames` ne pouvait pas l'activer. Les parrainages validés
entre ces deux dates ont reçu la récompense classique (accès à tous les jeux
jusqu'à minuit), et pas de ticket. C'est l'origine des 4 parrainages
« classiques » relevés dans la période du jeu.

## 3. Le bouton « Réparer le jeu »

- **Affichage** : seulement pour un jeu `ended`.
- **Action** : il lance en parallèle
  `adminReconcileReferralGameTickets` et `adminRepairReferralGameDraw`.
- **Réconciliation des tickets.** Pour chaque ticket, elle rappelle
  `addReferralGameTicket`, qui exige `status == "active"`. Sur un jeu
  terminé, elle ne crée donc **jamais** de ticket et renvoie toujours
  « 0 ticket(s) créé(s) ».
  - Ce serait d'ailleurs une erreur d'en ajouter après le tirage :
    le résultat ne serait pas équitable.
  - Depuis la file d'événements durable, un ticket ne peut plus manquer
    sans laisser un événement en attente ou à vérifier, et cet événement
    bloque le tirage. La réconciliation ne sert plus qu'aux parrainages
    antérieurs à cette file, sans événement. Aucun ne tombe dans la
    période du jeu actuel.
  - La version déployée n'a pas la protection de `fb56b4f`. Un appel
    direct sur le jeu actif pourrait ajouter jusqu'à 4 tickets, pour les
    parrainages déjà récompensés en classique. C'est la version 1.1.4 qui
    corrige ce point.
- **Réparation du tirage** (`repairReferralGameDraw`). Elle est utile :
  elle recrée le lot ou le lien `my_lots` d'un gagnant déjà tiré, sans
  changer ce gagnant.

## 4. Constats

| # | Constat | Gravité | Où |
|---|---|---|---|
| 1 | « Réparer le jeu » ne peut jamais recréer de ticket (voir §3) et annonce « 0 ticket(s) créé(s) » comme un succès. | moyenne | Admin et Functions |
| 2 | « Tirer le gagnant » affiche « Tirage terminé. » même si le moteur renvoie `manual_review_required` (récompense à vérifier) ou `already_finalized`. | moyenne | Admin `handleEnd` |
| 3 | L'API de mise à jour d'un jeu (`PATCH`) recopie tous les champs reçus (`...rest`) : elle peut écrire `winner_uid`, `draw_status`, `ticket_count`… Elle laisse aussi changer les dates d'un jeu actif ou déjà tiré. | moyenne | Admin API |
| 4 | La suppression d'un jeu actif sans ticket ne vérifie pas les récompenses en attente (`pending_reward_count` et événements `pending`). Un parrainage en cours de traitement perdrait sa récompense. | faible | Admin API |
| 5 | `autoManageReferralGames` active un brouillon dont la date de fin est déjà passée (pas de contrôle de fin). Le tirage de la nuit suivante le clôt sans participant. | faible | Functions |
| 6 | Quand un autre jeu est actif, le brouillon suivant reste inactif après sa date de début, sans alerte dans l'Admin (cas du 29 au 31/10). | moyenne | Functions et Admin |
| 7 | Entre la date de fin et le tirage de minuit, l'app affiche encore le jeu et promet un ticket par ami. Un parrainage validé à ce moment-là reçoit la récompense classique. | faible | App |
| 8 | Après le tirage, l'app n'affiche pas le gagnant. L'affichage dépend de `syncPublicPrizeWinner`, non déployée, et n'est pas intégré à la 1.1.4. | décision | App et Functions |
| 9 | Un jeu suspendu dont la date de fin est passée n'est jamais tiré tant qu'il n'est pas clôturé à la main. L'Admin propose bien « Clôturer », mais sans rappel. | faible | Admin |
| 10 | `referral_games` est lisible par tout joueur connecté, y compris `winner_uid` (identifiant technique du gagnant). | faible | Règles |
| 11 | Le nombre de tickets par parrain est illimité. Le 23/10, un plafond a été envisagé pour un jeu à gros lot. | décision | — |
| 12 | Le tirage lit tous les tickets et tous les comptes dans une seule transaction. Pas de problème avec 28 tickets, à surveiller au-delà de quelques centaines. | faible | Functions |

## 5. Proposition pour le bouton « Réparer le jeu »

Plutôt que de lui faire recréer des tickets (inutile depuis la file
durable, et inéquitable après un tirage) :

1. **Jeu terminé et tiré** : garder seulement la réparation du lot et de
   `my_lots` (`repairReferralGameDraw`). Afficher le vrai résultat :
   « rien à réparer », « lien réparé » ou « à vérifier ».
2. **Jeu terminé sans gagnant, ou actif** : remplacer le bouton par un
   **diagnostic**, qui lit les données sans les modifier. Il montrerait :
   - les tickets ;
   - les récompenses en attente ou à vérifier, avec leur motif ;
   - les parrainages acceptés dans la période sans événement (anciens
     parrainages) ;
   - la raison qui bloque le tirage.

   Tout ajout de ticket resterait une action séparée, réservée à un jeu
   **actif**, après un aperçu sans écriture (« dry run ») et avec la
   protection de `fb56b4f`.
3. **Corriger le message de « Tirer le gagnant »** selon le statut
   renvoyé (constat 2).

## 6. Décisions à prendre

1. **Bouton « Réparer le jeu »** : adopter la proposition du §5 ?
2. **API de l'Admin** :
   - limiter les champs modifiables à une liste fixe ;
   - figer les dates d'un jeu actif, ou autoriser seulement l'allongement de la fin ;
   - interdire toute modification après le tirage.
3. **Activation retardée par un autre jeu actif** : prévenir dans
   l'Admin, ou décaler automatiquement l'affichage de la date de début ?
4. **Fin de jeu dans l'app** : masquer la carte, ou afficher
   « Tirage en cours », dès la date de fin ?
5. **Affichage du gagnant** : déployer `syncPublicPrizeWinner` et
   réintégrer l'affichage (prénom et ville publics, voir la décision D5 de
   la suppression de compte) ?
6. **Plafond de tickets par parrain** pour les prochains jeux.
