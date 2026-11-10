# Réserve de parties bonus — ProxiPlay 1.1.4

Décision métier du 10/11/2026 : toutes les parties bonus gagnées sont
conservées, sans limite de durée et sans plafond. Elles sont tenues à part
des 3 parties quotidiennes.

Statut : implémenté et testé en local. Rien n'est poussé ni déployé, et
aucune donnée de production n'a été écrite.

## Règles implémentées

| Règle | Mise en œuvre |
|---|---|
| 3 parties par jour, remises à 3 à minuit (Paris) | `remaining_part`, géré par `resetDailyRemainingParts` (inchangé) |
| Bonus jamais effacés par le reset | nouveau champ `bonus_part`, que le reset n'écrit jamais |
| Parties du jour consommées d'abord, puis bonus | `planPlayConsumption` (`play_balance.js`), appelé dans la transaction de participation |
| Cumul sans plafond ni expiration | `bonus_part` ne fait qu'augmenter, jusqu'à ce que le joueur le consomme |
| Éligibilité des jeux inchangée | le contrôle du solde reste placé après les règles « déjà joué aujourd'hui », gratuité du QR du commerce et accès illimité |
| Accès « tous les jeux jusqu'à minuit » distinct | `allGamesAccessUntil` (parrainage) : ne consomme ni partie du jour ni bonus |
| Opérations atomiques, côté serveur uniquement | voir le détail sous ce tableau |
| Messages | 10e participation : « 3 parties bonus ! Elles sont conservées… ». Anniversaire : « 3 parties bonus, conservées jusqu'à ce que vous les jouiez ». |
| Solde consultable | barre du haut (« +N bonus »), carte « Mes parties » dans le profil, fiche joueur de l'admin intégré à l'app |

Détail de l'atomicité :
- Participation : lecture et écriture dans la même transaction Firestore.
- Anniversaire : transaction.
- Parrainage « parties » : `increment` dans une transaction.
- Règles Firestore : le joueur ne peut écrire `bonus_part` ni à la
  création ni à la mise à jour.

## Sources de parties bonus

| Source | Avant | 1.1.4 |
|---|---|---|
| 10e, 20e, 30e… participation à un jeu | +3 `remaining_part`, perdues à minuit | +3 `bonus_part`, conservées |
| Anniversaire (automatisation active) | +3 `remaining_part` « aujourd'hui » | +3 `bonus_part` ; l'événement indique `credited_to: "bonus_part"` |
| Récompense de parrainage de type « parties » (non utilisée en production) | `remaining_part` | `bonus_part` |
| Parrainage `all_games_until_midnight` (configuration actuelle) | accès illimité jusqu'à minuit | inchangé |

## Réponse de la participation

Champs ajoutés, que les anciennes versions de l'app ignorent :
- `playSource` : `daily`, `bonus`, `free` ou `unlimited` ;
- `remainingPart` et `bonusPart` : soldes après la partie.

## Compatibilité et déploiement

- **Anciennes versions de l'app.** Elles ne connaissent pas `bonus_part`.
  Un joueur qui n'a plus de parties du jour mais garde des bonus verra le
  bouton « plus de parties », car le blocage se fait côté client. Le serveur
  accepterait pourtant la partie. Les bonus restent conservés et seront
  utilisables dès la mise à jour.
- **Ordre de déploiement :**
  1. Functions : `participateInGameTransaction`, les automatisations
     d'anniversaire et les fonctions de parrainage. Chaque groupe doit être
     comparé avant envoi, voir le plan Node 22.
  2. Règles Firestore.
  3. App.

  Les règles ne bloquent rien d'existant : `bonus_part` était déjà absent
  de la liste blanche des mises à jour par le joueur.
- **Joueurs ayant plus de 3 parties du jour.** 6 joueurs le 10/11. Ces
  parties restent des parties du jour et redescendent à 3 au prochain
  minuit, comme aujourd'hui. Les convertir en bonus demanderait une
  migration de données en production, non prévue ici et à décider
  séparément.
- **Texte de la notification d'anniversaire.** La production utilise
  l'ancien texte « Profitez de vos avantages du jour… ». Le code le remplace
  à l'envoi par le nouveau texte par défaut, donc aucune écriture en
  production n'est nécessaire. Un texte personnalisé saisi plus tard dans
  l'Admin primerait.
- **Inchangé :**
  - la relance de 18:00 cible toujours les joueurs à qui il reste des
    parties du jour ;
  - le reset réécrit toujours tous les joueurs chaque nuit. L'optimisation
    reste proposée dans `bonus-plays-audit-1.1.4.md`.

## Tests

| Suite | Résultat |
|---|---|
| `bonus_plays` (nouveau, émulateurs) | 13 cas : ordre de consommation, refus sans solde, accès illimité distinct, passage à minuit, 10e participation, cumul sans plafond, participations simultanées, éligibilité inchangée, règles Firestore |
| Tests modifiés selon la nouvelle règle | `game_lifecycle_classic`, `game_lifecycle_qr`, `game_lifecycle_shop_qr_play` (le +3 va dans `bonus_part`), `birthday_reward` (crédit et message) |
| Flutter `play_balance_test` (nouveau) | 6/6, dont l'affichage sur un écran de 320 px de large |
