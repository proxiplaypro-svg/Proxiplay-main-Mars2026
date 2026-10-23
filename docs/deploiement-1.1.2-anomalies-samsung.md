# ProxiPlay 1.1.2 — déploiement des corrections Samsung

Procédure préparée, **non exécutée**. Projet de production : `proxi-play-odzp2e`.
Ordre impératif : index, puis fonctions, puis migration, puis Admin, puis application.

## 0. Avant de commencer

- Vérifier que la branche contient bien tout le travail local (Codex + Claude) et que les tests passent :
  - `firebase/functions` : `npx tsc -p .` puis les suites sur émulateur `demo-` ;
  - application : `flutter test` ;
  - Admin : `npx tsc --noEmit -p .` et `node --test merchant-referral-toggle-ui.test.mjs`.
- `index.js` et `lib/` contiennent aussi d'autres travaux en cours : déployer **uniquement** les fonctions listées ci-dessous, jamais `firebase deploy --only functions` sans filtre.

## 1. Index Firestore (anomalie 4)

```
firebase deploy --only firestore:indexes --project proxi-play-odzp2e
```

Deux nouveaux index composites sur `prizes` : `owner_id + claim_code_search` et `enseigne_id + claim_code_search`.
Attendre l'état « Activé » dans la console Firebase avant l'étape 3 : sans eux, la recherche échoue et l'application affiche « Suggestions indisponibles ».

## 2. Cloud Functions

```
cd firebase/functions
npx tsc -p .
firebase deploy --project proxi-play-odzp2e --only \
functions:searchMerchantPrizeCodes,\
functions:syncPrizeSearchCode,\
functions:getMerchantPrizes,\
functions:pickEndedMainPrizeWinners,\
functions:pickMainPrizeWinners,\
functions:createReferral,\
functions:createReferralEmailAccount,\
functions:registerReferralAcceptance,\
functions:grantReferralReward,\
functions:retryReferralRewards,\
functions:expireOldReferrals,\
functions:generateMerchantReferralCode
```

| Fonction | Anomalie | Changement |
|---|---|---|
| `searchMerchantPrizeCodes` | 4 | Nouvelle : suggestions de codes gagnants (absente en production). |
| `syncPrizeSearchCode` | 4 | Nouvelle : maintient `claim_code_search` à chaque écriture de lot. |
| `getMerchantPrizes` | 4 | Limite de débit partagée avec la recherche. |
| `pickEndedMainPrizeWinners` | 3 | Nouvelle, chaque minute : tire les jeux clôturés depuis moins de 48 h. Cloud Scheduler crée la tâche au déploiement. |
| `pickMainPrizeWinners` | 3 | Inchangée sur l'horaire (minuit) ; prénom du gagnant avec repli `display_name` / `pseudo`. |
| `createReferral`, `createReferralEmailAccount`, `registerReferralAcceptance`, `grantReferralReward`, `retryReferralRewards`, `expireOldReferrals` | 5 | Suppression des plafonds, flux d'inscription sécurisé, file de récompenses fiable. |
| `generateMerchantReferralCode` | 1 | Respect du réglage `app_config/merchant_referral`. |

Contrôle après déploiement, en lecture seule : journaux `pickEndedMainPrizeWinners` → `DRAW_RUN_STARTED` toutes les minutes, `DRAW_SUCCESS` pour les jeux clôturés.
Un `AWARD_MANUAL_REVIEW_REQUIRED` signale un jeu bloqué par une incohérence (boutique, lot existant, date limite) : il reste « Tirage au sort en attente » jusqu'à correction manuelle. Ne pas relancer de tirage sur un jeu réel sans analyse.

## 3. Migration des anciens codes gagnants (anomalie 4)

Les lots créés avant `syncPrizeSearchCode` n'ont pas `claim_code_search` et ne sont pas suggérés.

```
cd firebase/functions
# Simulation : compte seulement les lots à compléter
node scripts/backfill_prize_search_codes.js --project proxi-play-odzp2e
# Écriture, après validation du chiffre « pending »
node scripts/backfill_prize_search_codes.js --project proxi-play-odzp2e --apply
```

Le script n'écrit que `claim_code_search` (copie normalisée de `claim_code`) et peut être relancé sans effet.
Chaque écriture déclenche aussi les autres déclencheurs `prizes/{id}` existants : lancer hors des heures de pointe.

## 4. Jeux déjà terminés sans nom de gagnant (anomalie 3)

- Jeu **non tiré** et clôturé depuis moins de 48 h : tiré automatiquement dans la minute suivant le déploiement. Plus ancien : au passage de minuit.
- Jeu **tiré** mais sans prénom (gagnant sans `first_name`) : utiliser l'outil admin existant `backfillWinnerDisplayFields` d'abord avec `dryRun: true`. Il recopie uniquement le prénom et la ville, sans nouveau tirage.

## 5. Admin (anomalie 2)

Déployer le dépôt `admin-proxiplay` selon la procédure Vercel habituelle.
L'interrupteur du parrainage commerçant apparaît dans **Parrainage joueurs** (`/admin/parrainage`) et dans **Parrainage commerçants**, tous deux dans la rubrique Communication.

## 6. Application

Construire l'APK ou l'AAB de recette sans changer la version, puis dérouler la recette Samsung.
