# ProxiPlay 1.1.4 — audit technique et fonctionnel (09/11/2026)

Branche `release/proxiplay-1.1.4`, issue de `ff277af` (1.1.3+75). Aucun
déploiement, aucune écriture en production. Lectures de production : métadonnées
des Functions, archives sources (téléchargées, comparées puis supprimées) et une
trentaine de lectures Firestore ciblées (voir §3).

Légende : **[T]** terminé et testé · **[M]** modifié, validation incomplète ·
**[A]** analysé seulement · **[D]** en attente de décision.

## 1. Tests

| Suite | Résultat |
|---|---|
| Functions, 104 fichiers, Node 20, avant intervention | 1.1.3 et 1.1.4 : mêmes 13 échecs + 1 annulé |
| Functions, après interventions, Node 22.23.4 | 880 tests, 879 réussis, 1 échec (§5.1) |
| Scénario QR 350 instants (long, isolé) | 4/4 en 11 min |
| `flutter analyze` | 0 erreur, 23 avertissements, 163 infos (base 1.1.3) |
| `flutter test` | 724/724 après correction d'un test (§2) |

Origine des 14 cas de la 1.1.3 :

| Cas | Nature | Traitement |
|---|---|---|
| `notify_prize_won_managed_by_admin` (5) | test obsolète (règle remplacée le 28/09) | [T] test aligné, 3 cas ajoutés |
| `merchant_prizes` (3-4) | environnement : SDK Admin sur un autre projet | [T] projet explicite dans le test |
| `storage_rules_ads` (3) | environnement : émulateur Storage absent | [T] 3/3 avec Storage |
| `scenario_qr_year_350_instants` (1) | environnement : délai de 120 s | [T] 4/4 sans délai court |
| `game_lifecycle_instant` (1) | règle de jeu à trancher | [D] voir §5 |
| `operator_prize_claim` | jamais en échec (erreur d'attribution initiale) | — |

## 2. Commits

| Commit | Contenu | Statut |
|---|---|---|
| `c93d2bf` | Fusion de la partie serveur de Stripe (site proxiplay.fr) ; exclusions app/règles documentées | [T] |
| `c75a145` | `fb56b4f` : suspension du jeu du parrainage, garde anti-double récompense | [T] |
| `69e31ea` | Test `notify_prize_won_managed_by_admin` aligné sur la règle de remise | [T] |
| `3106389` | E-mail/push d'un gain au jeu du parrainage sans « chez <enseigne> » | [T] |
| `b3d87df` | Test de la règle `public_content/active_catalog` | [T] |
| `dc00606` | `merchant_prizes.test.js` : projet Admin explicite | [T] |
| `fc26e78` | Test source de l'annuaire : fins de ligne CRLF normalisées | [T] |

## 3. Parrainage : `adminReconcileReferralGameTickets`

- Code déployé = `3789584` à l'identique (210/210 fichiers, archive du 02/11
  12:31 UTC) : la garde anti-double récompense de `fb56b4f` est **absente**.
- Exécution : callable admin uniquement. L'Admin l'appelle par « Réparer le
  jeu », affiché seulement pour un jeu `ended` ; sur un jeu terminé la fonction
  ne crée aucun ticket (`status !== 'active'` → `ineligible`).
- Exposition : nulle via l'Admin. Par appel direct sur le jeu actif
  `SZgZkvzuTSkHSIjuJSO1` (28/10 → 04/12) : jusqu'à 4 tickets en trop (4
  parrainages récompensés en classique dans la période, sans ticket). Aucun
  jeu suspendu ni réactivation refusée en production. Risque réel : faible.
- Correctif : intégré (`c75a145`), testé (`referral_game_suspension`, 4/4 ;
  parrainage 50/50). Redéploiement à décider (§6).
- Défaut annexe [D] : « Réparer le jeu » ne peut jamais recréer un ticket
  perdu (bouton limité aux jeux terminés, fonction limitée aux jeux actifs).

## 4. Règle des notifications de gain (établie, inchangée)

Source : `prize_merchant_notification_policy.js` (6a16eda) et Admin
`planGameFulfillment`.

| Contrat du lot (`fulfillment_type`) | Qui remet | Joueur | Commerçant |
|---|---|---|---|
| `merchant` (enseigne avec compte, choix « commerçant ») | commerçant | e-mail + push | e-mail + push « Nouveau gagnant », même enseigne administrée |
| `platform` (choix « ProxiPlay ») | ProxiPlay | e-mail + push (« Remise organisée par ProxiPlay ») | rien (`platform_delivery`) |
| `partner` (enseigne sans compte) | partenaire | e-mail + push | rien (`partner_delivery`) ; liste par `deliverPartnerPrizeDigests` |
| absent (lots historiques) | — | e-mail + push | rien si `managed_by_admin` (`managed_by_admin_legacy`) |

## 5. Décisions métier à prendre

1. **Réparation d'un calendrier d'instants gagnants** (`game_lifecycle_instant`) :
   depuis `11dfab9` (06/10), une réparation admin sur un jeu commencé replanifie
   aussi un instant passé non gagné (créé 2, attendu 1). Un instant passé non
   gagné doit-il rester « dû » (gagné par le prochain joueur) ou être
   replanifié ? Code et test laissés en l'état.
2. **Bonus** : `resetDailyRemainingParts` remet chaque joueur à 3 parties à
   minuit (Paris) ; aucun report des parties bonus. Conserver ou non ?
3. **Date de naissance modifiable par le joueur** (`isSafeSelfUserUpdate`) : elle
   conditionne les jeux et publicités réservés aux majeurs et l'éligibilité
   marketing. La figer après saisie ?
4. **Jeu du parrainage** : redéployer `adminReconcileReferralGameTickets` depuis
   1.1.4 (garde) et corriger le bouton « Réparer le jeu » ?
5. **`syncPublicPrizeWinner` et `pickEndedMainPrizeWinners`** (dans le code,
   absentes de la production) : déployer ou non.

## 6. Node 22 — 56 fonctions de l'app encore en Node 20

Aucune n'exécute le code de la 1.1.4 : `index.js`, `email_sender.js` et
`package.json` diffèrent dans les 12 groupes (archives comparées fichier par
fichier). Redéployer depuis 1.1.4 apporte donc toujours du code nouveau.

| Groupe (source d'après MIGRATION-NODE22.md) | Nb | Fonctions | Stratégie proposée |
|---|---|---|---|
| G2 L01 `28237fa` | 23 | push, rappels, compteurs, init comptes… | iso-production (commit source + engines 22), 3-4 sous-lots |
| G3 L04 `5c0de1c` | 9 | claimOperatorPrize, deleteCommercantAccount, deliverPartnerPrizeDigests, drawAnimationWinners… | iso-production |
| G11 L05 `850a10f` | 2 | anniversaires | iso-production (hors 08:00-10:00) |
| G5 L11 `adb345f` | 1 | drawMonthlyChallengeWinner | iso-production (hors le 1er) |
| G9 L10 `4c87e82` | 1 | refreshGooglePlaceRating | iso-production |
| G4 + G8 L12 `f84db24` | 5 | createReferral, grantReferralReward, notifyReferralBonusEmail, recordAdEvent, getRestrictedAdCreative | iso-production, heure creuse |
| G10 L09 `00148af` | 1 | relaunchInactiveMerchants | iso-production (module identique à 1.1.4) |
| G1 L13 `6ba5f99` | 8 | autoManageReferralGames, drawReferralGameWinner, inscriptions parrainage… | iso-production, après le passage de 14:30 |
| G0 L10 `4c87e82` | 4 | notifyPrizeWon, getMerchantPrizes, searchMerchantPrizeCodes, syncPrizeSearchCode | **depuis 1.1.4** (texte parrainage, quotas « Vérifier ») |
| G6 `fb56b4f` | 1 | enforceSingleActiveReferralGame | **depuis 1.1.4**, avec adminReconcileReferralGameTickets |
| G7 L07 `41ebff0` | 1 | generateInstantWinnersForGame | après la décision §5.1 |

Hors périmètre : 14 fonctions Admin (gen2), 4 orphelines. Attention :
`unlockCommercantAccount` (orpheline) est appelée par l'écran admin de l'app
(`commercant_admin_detail_page_widget.dart`) ; ne jamais la supprimer.

Compatibilité : 51 fonctions tournent déjà en Node 22 avec le même
`package.json` (firebase-functions 4.9.0, firebase-admin 11.11.1) ; suite des
Functions sous Node 22 : §7. Points de vigilance : `functions.config()`
(repli SMTP de `smtp_config.js`, `google_places_search_callable.js`) dépend de
Runtime Config, dépréciée ; vérifier à chaque déploiement que
`.runtimeconfig.json` est toujours embarqué (présent dans l'archive du 02/11).

## 7. Functions sous Node 22

Suite complète (103 fichiers, scénario QR 350 exécuté à part) avec Node
22.23.4, émulateurs Firestore + Auth + Storage, après tous les commits de la
session : **880 tests, 879 réussis, 1 échec** — le cas `game_lifecycle_instant`
en attente de décision (§5.1), identique sous Node 20. Aucune incompatibilité
Node 22 constatée.

## 8. Audit fonctionnel de l'app (analyse de code, sans appareil)

| Domaine | Constat | Statut |
|---|---|---|
| Intégrité des participations | Participation, QR, tickets, lots : écrits par le serveur seulement ; `participants` et `prizes` sans création client ; profil joueur limité à une liste blanche (aucun champ de jeu) | [A] solide |
| Fonctions appelées par l'app | 19 callables ; toutes existent en production ; `unlockCommercantAccount` absente du code (orpheline) | [A] |
| Haptique | 4 appels centralisés (`utils/haptics.dart`, `widgets/tap_feedback.dart`) | [A] |
| Accessibilité | 8 `Semantics`, 2 libellés pour 69 images, 6 tooltips | [A] faible |
| Performances | 51 écouteurs Firestore ; Home 12 ; compteurs de tickets = écoute de toutes les participations du joueur sur le jeu (coûteux sur un jeu QR annuel) | [A] |
| Coût serveur | reset quotidien = lecture + écriture de tous les joueurs chaque nuit | [A] |
| Dépendances Functions | 9 paquets jamais importés (5 @langchain, @mux, @onesignal, braintree, razorpay) ; `npm run lint` inutilisable (pas de config ESLint, chemin Unix) | [A] |
| Règles Storage | `isAdmin()` lève une erreur pour un jeton sans `admin`/`email` (refus correct, journaux bruyants) | [A] |

## 9. Recommandations (utilité / complexité / risque)

| # | Recommandation | Utilité | Complexité | Risque |
|---|---|---|---|---|
| 1 | Redéployer G0 + G6 + reconcile depuis 1.1.4 (§6) | haute | faible | moyen (fonctions critiques : heure creuse, retour arrière prêt) |
| 2 | Migration iso-production des autres groupes, par lots | haute | moyenne | faible |
| 3 | Compteur de tickets par `count()` ou champ serveur | moyenne | faible | faible |
| 4 | Reset quotidien limité aux joueurs `remaining_part != 3` | moyenne | faible | moyen (job critique) |
| 5 | Retirer les 9 dépendances inutilisées (commit dédié, suite complète) | moyenne | faible | faible, mais change le lockfile de tous les déploiements suivants |
| 6 | Accessibilité : `semanticLabel` des images, `Semantics` sur les cartes de jeu | moyenne | moyenne | faible |
| 7 | Remplacer Runtime Config (SMTP, Google Places) par params/secrets | haute à terme | moyenne | moyen (configuration de production) |
| 8 | Configuration ESLint fonctionnelle sous Windows | basse | faible | nul |
| 9 | `storage.rules` : test `'admin' in request.auth.token` comme `firestore.rules` | basse | faible | faible (règles de production) |
