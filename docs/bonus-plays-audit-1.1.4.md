# Parties bonus — audit et options (ProxiPlay 1.1.4)

Statut au 10/11/2026 : audit en lecture seule. Aucune règle de jeu n'a été
modifiée. Les données de production citées viennent de comptages anonymes
(`count()`) et de deux documents de configuration lus sans modification.

## 1. Fonctionnement actuel

### Le compteur `remaining_part`

- Il est écrit uniquement par le serveur.
- Une partie normale le diminue de 1. Une partie jouée en scannant le QR du
  commerce ne le diminue pas, et un accès illimité (`allGamesAccessUntil`)
  non plus.
- Un joueur à 0 ne peut plus jouer, sauf en scannant le QR du commerce ou
  s'il a un accès illimité.
- Chaque jeu ne peut être joué qu'une fois par jour et par joueur. C'est le
  « déjà joué aujourd'hui », vérifié jeu par jeu, indépendamment du compteur.

### Le reset de minuit (`resetDailyRemainingParts`, 00:00, heure de Paris)

- Il met **tous** les joueurs à `remaining_part = 3`, quel que soit leur
  solde. Les parties non jouées ne sont pas reportées : un bonus non utilisé
  est perdu, et un solde de 3 ou plus redescend à 3.
- Il réécrit les 1 744 joueurs chaque nuit, y compris ceux déjà à 3, car
  `part_last_update` change à chaque fois.
- Chaque réécriture déclenche les 2 fonctions `onUpdate` sur `users`
  (`initializePlayerRemainingPartsOnRoleAssignment` et
  `initializeMerchantAccountStatusOnRoleAssignment`), soit environ 3 500
  exécutions par nuit pour rien.

### Les sources de parties en plus

| Source | Effet | Message au joueur | Après minuit |
|---|---|---|---|
| 10e, 20e, 30e… participation **à un jeu** (`participations % 10 == 0`) | +3 `remaining_part` | « Vous avez gagné 3 parties supplémentaires ! » | perdu, sans que le message l'annonce |
| Anniversaire (automatisation active, 09:00) | +3 `remaining_part`. La configuration de production dit `all_games_until_midnight`, que le code transforme en +3 parties. | « …3 parties supplémentaires aujourd'hui ! » | perdu, ce qui est cohérent avec « aujourd'hui » |
| Parrainage (configuration de production : `all_games_until_midnight`) | accès illimité jusqu'à minuit (`allGamesAccessUntil`) | « jouer à tous les jeux jusqu'à minuit » | prend fin à minuit, sans lien avec le reset |
| `game_bonus` (dans `participants_details`) | permet de rejouer le même jeu le même jour | — | aucun code ne le met au-dessus de 0, et aucun ne le décrémente |

### En production le 10/11 à 13:18

| Solde `remaining_part` | Nombre de joueurs |
|---|---|
| 3 | 1 702 |
| 0 | 94 |
| plus de 3 | 6 (dont 3 à 6 ou plus) |
| moins de 0 | 0 |

- 1 accès illimité en cours.
- `reward_events` : 681 récompenses de parrainage (`all_games_until_midnight`)
  et 165 crédits d'anniversaire, sur 855 au total.

## 2. Constats indépendants de la décision

1. **Le message du bonus de la 10e participation** ne dit pas que les
   parties expirent à minuit. Un joueur qui les gagne à 23:50 les perd 10
   minutes plus tard.
2. **Ce bonus récompense le 10e participant du jeu**, quel qu'il soit, et
   non la 10e participation du joueur. Est-ce voulu ?
3. **`game_bonus` n'est géré qu'à moitié.** Si une valeur au-dessus de 0
   était écrite un jour, à la main ou par un futur code, le joueur pourrait
   rejouer ce jeu sans limite dans la journée, car elle n'est jamais
   décrémentée.
4. **Le reset coûte cher** : 1 744 écritures et environ 3 500 exécutions de
   fonctions par nuit, alors qu'environ 140 joueurs seulement ont un solde
   différent de 3.

## 3. Options pour les nouvelles règles

| Option | Règle | Avantages | Limites |
|---|---|---|---|
| **A. Statu quo clarifié** | Tout expire à minuit. Le message dit « valables jusqu'à minuit ». | Aucun changement de règle. | Le bonus reste frustrant s'il arrive tard. |
| **B. Plancher quotidien** | À minuit, `remaining_part = max(solde, 3)`, avec un plafond à fixer (par exemple 10). | Peu de code. Le bonus est conservé. Le reset n'écrit plus que les soldes sous 3, environ 94 joueurs ce jour-là. | Bonus et parties du jour sont mélangés. L'anniversaire « aujourd'hui » devient faux, à reformuler. |
| **C. Deux compteurs** | `remaining_part` (3 par jour, remis à 3) plus `bonus_part` (reporté, consommé après les parties du jour, avec expiration, par exemple 30 jours). | Règle nette et affichable (« 3 + 2 bonus »). Durée de validité au choix. | Plus de travail : participation, app, relance de 18:00, Admin et migration. |

Ma recommandation : **B avec un plafond**, comme un juste milieu. Elle
corrige la frustration principale et réduit fortement le coût du reset.
Il faudra reformuler le message d'anniversaire en « 3 parties offertes ».
L'option C n'est utile que si tu veux afficher les bonus à part ou leur
donner une date d'expiration.

## 4. Décisions à prendre

1. **Option A, B ou C.** Pour B : le plafond. Pour C : la durée de validité
   des bonus.
2. **Bonus de la 10e participation** : garder la règle du 10e participant
   du jeu, ou passer à la 10e participation du joueur ?
3. **Anniversaire** : +3 parties « aujourd'hui » seulement, ou reportables
   comme les autres bonus ?
4. **`game_bonus`** : le supprimer (recommandé, aucune source ne l'alimente)
   ou en définir la règle ?

Indépendamment de ces décisions, une correction est possible sans changer
les règles : ne plus réécrire les joueurs dont le solde est déjà 3. Elle
demande un index Firestore (`remaining_part`), donc un déploiement de
configuration.
