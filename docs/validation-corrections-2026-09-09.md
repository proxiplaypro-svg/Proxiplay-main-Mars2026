# Validation des corrections — 9 septembre 2026

Cette phase reprend la checklist de l'audit critique du 8 septembre, conservé dans `audit-complet-2026-09-08.md`. Elle corrige le code sur **develop**. Aucun déploiement, push, audit distant ou changement de données distantes n'a été exécuté.

## A. Nouvelle note

**B pour le code corrigé et validé localement.** La production ne peut pas être reclassée sur la seule base de Git : sa note reste **C non réévaluée**, jusqu'à la bascule des lecteurs mobiles, des rules, des indexes et des Functions, puis vérification des données historiques et des exécutions réelles.

Les P0/P1 traités ci-dessous disposent d'une correction locale. Les derniers verrous sont externes : compatibilité des versions mobiles et de la console admin indépendante, déploiement, historique à examiner et modalités de remise des lots plateforme/partenaire.

## B. Risques et validation

| Risque | Avant | Correction | Tests | Reste à faire | Prod requise |
|---|---|---|---|---|---|
| P0 privilèges | Alias admin et ajouts/suppressions de champs sensibles | Contrôle de `userRole`, `affectedKeys()` | Émulateur : inscription frauduleuse, ajout/suppression protégés | Déployer | Rules |
| P0 prizes publics | Documents complets accessibles, dont codes | Rules strictes ; projection publique minimale ; ticker adapté | Lecture publique refusée, gagnant/propriétaire autorisés, projections serveur uniquement | Bascule mobile progressive | Rules, Functions, mobile |
| P0 merchants/jeux | Relation propriétaire fabricable | Création admin ; UID/références fiables ; whitelist d'édition ; aucune propriété par email | Escalade par email, document forgé, modification owner refusées | Vérifier les anciens propriétaires dans la console externe | Rules, données |
| P0 tirage principal | Compte inexistant/supprimé/suspendu sélectionnable | Filtrage avant attribution ; écritures atomiques ; propriétaire réel | Actif, manquant, supprimé, suspendu, mixte, zéro/tous exclus, concurrence, rollback | Vérifier historique | Functions |
| P0 prize/my_lots | Réparation de liens contradictoires possible | Vérification gagnant/source/utilisateur/canonique ; recherche des liens chez tous les utilisateurs ; `manual_review_required` | Mauvais gagnant source, mauvais canonique, doublon, autre owner, compte/source absents | Examiner les contradictions ; aucune réparation globale lancée | Functions, index |
| P0 acceptation sans ticket | Panne entre acceptation et attribution | Événement durable dans la transaction d'acceptation ; traitement idempotent ; retry planifié ; tirage bloqué tant qu'événements non résolus | Callable réel avec panne après commit, retry/concurrence, jeu terminé, tirage final, ticket existant | Examiner anciennes acceptations sans événement | Functions, indexes |
| P1 double animation | Écriture Flutter legacy concurrente | Suppression `animation_utils.dart` ; progression/qualification renvoyées et mises en cache par le serveur | Qualification serveur et rejeu sans nouvelle annonce ; parsing Flutter | Distribuer le mobile | Functions, mobile |
| P1 gagnant invisible | Lecture d'un document privé refusée | `public_winner/current` atomique avec le tirage ; deux lecteurs Flutter adaptés ; backfill ciblé create-only | Rules, contenu minimal, ancien tirage sans projection, dry-run/retry | Backfill contrôlé après audit | Functions, mobile, données |
| P1 crons | Échecs absorbés | Runner commun ; `DRAW_QUERY_FAILED`, `DRAW_FAILED`, `DRAW_SKIPPED`, `DRAW_SUCCESS` ; rejet global ; imports requis non silencieux | Requête en échec, échec individuel et poursuite, retry et transactions | Contrôler Scheduler, logs et alertes réelles | Functions |
| P1 indexes | Déclarations incomplètes | Indexes critiques et contrat versionné ; file de reprise et group my_lots inclus | Contrat des indexes | Attendre l'état READY ; émulateur ne prouve pas leur déploiement | Indexes |
| P1 visibilité admin/commerçant | `create_by`, limite 15 | `owner_id`, fallback enseigne ; curseur commun par ID, fusion/dédoublonnage ; bouton de pagination ; agrégats parcourant les pages | 37 jeux, créateurs admin/commerçant, deux enseignes, trois statuts, absence de fuite entre propriétaires | Déployer callable avant mobile ; vérifier admin externe | Functions, mobile |
| P1 remise des lots | Circuit implicite | Nouveaux lots merchant/platform explicites ; platform/partner non validables par commerçant ; fallback prudent | Lot plateforme avec ancien owner non validable | Définir remise et partenaires autorisés | Rules, Functions, mobile |
| P2 Mes lots | Stream puis lectures ponctuelles obsolètes | Snapshot privé whitelist dans my_lots, sans recréer les liens supprimés ; détail abonné ; expiration recalculée localement | Claim/expiration actualisés, événement répété, mauvais owner, absence de résurrection | Observer coûts et volumes réels | Functions, mobile |
| P2 Google | Réponse B pouvant écraser C | Relecture transactionnelle du place ID avant mise à jour ou effacement | Réponse B tardive refusée | Aucun refresh périodique ajouté | Functions |

## C. Fichiers et contrats

- `firebase/firestore.rules`, `firestore.indexes.json` : sécurité canonique et indexes.
- `firebase/firestore.legacy-prizes.rules`, `firebase.rollout.json` : étape temporaire explicite de compatibilité. **Elle conserve le P0 de lecture publique des prizes** et ne constitue pas l'état final sécurisé.
- `main_prize_draw.js`, `prize_integrity.js`, moteurs animation/referral/mensuel, `prize_my_lots_repair.js` : attribution et réparation contrôlées.
- `referral_reward_queue.js`, `src/share_promo/*` et bundle `lib/share_promo/*` : acceptation durable, retry et garde de clôture. Les bonus classiques vérifient aussi l'existence et l'éligibilité du parrain.
- `public_winners.js`, `scripts/backfill_public_winners.js` : projections publiques sans email, téléphone, code ou UID utilisateur ; prénom limité au premier mot, champs de contact rejetés.
- `merchant_games.js`, `lib/services/merchant_games_service.dart` et pages commerçant : pagination et contrat de propriété. Aucun schéma de jeu multi-enseigne n'a été trouvé ; plusieurs enseignes d'un même propriétaire sont prises en charge. Un owner explicite contradictoire est exclu.
- `prize_lot_snapshot.js`, pages lots/détail, `PrizesRecord` : fraîcheur et remise explicite.
- `google_place_rating_refresh.js` : protection contre réponses désordonnées.
- `scripts/audit_game_integrity.js` : reste exclusivement en lecture seule, avec détection des propriétaires incohérents, projections absentes, acceptations sans ticket et circuits de remise incomplets.
- Tests Functions et Flutter : scénarios de sécurité, transaction, reprise, pagination et lecture.

### Lecteurs de prizes recensés dans ce dépôt

| Lecteur | Contrat après correction |
|---|---|
| Mes lots, profil joueur et détail lot | Références du gagnant connecté ; my_lots privé ; détail limité au lot ouvert |
| Ticker global, fallback historique | `public_prize_winners` ; plus aucune lecture de profil utilisateur pour compléter l'affichage |
| Gagnant animation, accueil joueur | `animations/{id}/public_winner/current` |
| Accueil commerçant, validation, détail jeu commerçant | Lots liés à `owner_id` ou enseigne détenue ; queries de propriété conservées et testées |
| Pages de jeux publiques | Données publiques du jeu ; aucune nécessité locale restante de lire les prizes complets |
| Notifications, statistiques globales, tirages et outils admin Functions | Admin SDK serveur ; ne dépendent pas de `allow read: if true` |
| Console admin indépendante | Dépôt absent : vérifier ses lecteurs et UID/claims admin avant bascule |

Aucun écrivain Flutter ou Functions de la collection legacy `merchants` n'a été trouvé dans ce dépôt. Les rules `/jeux` utilisent encore cette relation ; elle est donc conservée avec propriété attribuée par admin/serveur. Une relation fondée seulement sur l'email doit être provisionnée avec une référence fiable avant usage.

### Coûts et limites explicites

La liste des lots conserve **un stream my_lots**, aucun stream par prize. Les snapshots déjà présents évitent les lectures `prize.get()` ; les anciens liens ont un fallback ponctuel. Le cache de chargement évite de répéter ces lectures à chaque recalcul local d'expiration. Le détail ouvre **un stream pour un lot**, fermé à sa sortie. Une modification serveur d'un prize ajoute une écriture par lien légitime existant ; les liens d'un autre bénéficiaire ne sont pas enrichis. La latence d'affichage dépend du trigger ; l'expiration affichée est recalculée au plus tard à la minute suivante, les rules restant l'autorité immédiate.

La pagination commerçant interroge deux branches owner et deux branches par enseigne, limitées à 21 documents par branche pour une page de 20. Les IDs sont fusionnés avant progression du curseur : aucun jeu non examiné n'est sauté. Les agrégats parcourent toutes les pages ; ils ne sont plus limités arbitrairement à 500, mais leur coût croît avec le nombre de jeux. Le mobile doit être distribué après le callable `getMerchantGames` en `europe-west1`.

## D. Tests exécutés

Résultats définitifs :

- Suite Functions : **259 réussis, 0 échec, 0 ignoré**, 2 suites, 106,5 secondes.
- SMTP isolé : **2 réussis**, aucun envoi réel. Total Functions : **261 réussis**.
- Après suppression des objets d'erreur SMTP des logs animation : les **8 tests animation** repassent.
- Flutter : **81 réussis**, y compris le nouveau contrat de qualification serveur.
- TypeScript : compilation réussie via le compilateur local du dépôt.
- Analyse Flutter : **0 erreur, 24 avertissements, 166 informations** ; la commande reste non verte pour ces diagnostics (190 au total, contre 194 dans l'audit initial).
- `git diff --check` : réussi.

Une première suite complète avait 257 réussites et un échec sur une fixture de lot historique sans source. La fixture de réparation légitime contient maintenant une source existante ; les cas de source absente restent explicitement bloqués et testés. La suite finale de 259 tests passe.

```powershell
# Firestore 8080 et Auth 9099 locaux uniquement
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FUNCTIONS_EMULATOR = 'true'
$tests = @(rg --files firebase/functions/test -g '*.test.js' |
  Where-Object { $_ -notmatch 'notify_prize_won_idempotence' })
node --test --test-concurrency=1 $tests
Remove-Item Env:FUNCTIONS_EMULATOR
node --test firebase/functions/test/notify_prize_won_idempotence.test.js
# Depuis firebase/functions :
node node_modules/typescript/bin/tsc
# Depuis la racine :
flutter test --no-pub
flutter analyze --no-pub
git diff --check
```

SMTP est testé séparément avec Nodemailer remplacé : aucun email réel. Le test est incompatible avec le mode qui désactive volontairement les envois. Firestore 1.21.0 du cache local a été utilisé avec Java 21 en anglais ; le téléchargement CLI 1.22.0 échouait sur la chaîne TLS. Aucun contrôle TLS n'a été désactivé. Une relance a échoué à se connecter après arrêt des émulateurs ; ce résultat d'environnement n'est pas présenté comme validation du code.

## E. Actions production, non exécutées

1. **Indexes** : publier les déclarations, attendre READY, vérifier les requêtes réelles. Présent dans Git ≠ déployé.
2. **Functions** : publier moteurs, participation, file et retry, projections, snapshot de lots, callable commerçant et garde Google. Vérifier Scheduler/permissions, exécuter des scénarios de recette et observer les échecs visibles. Un cron compilé n'est pas déclaré opérationnel en production.
3. **Rules** : étape de compatibilité possible via `firebase.rollout.json`, puis rules strictes canoniques via `firebase.json`. Ne pas déployer les rules strictes tant que les clients requis lisent encore les prizes publics.
4. **Mobile** : publier les nouveaux lecteurs, qualification serveur, pagination et lots ; décider la version minimale et la durée de coexistence.
5. **Migration/backfill** : audit distant en lecture seule, revue des anomalies, puis projections ciblées. Script : `node scripts/backfill_public_winners.js --project=PROJECT --type=animation --id=ID` (dry-run), `--apply` seulement après validation des cibles. Même contrat pour `--type=prize`. Aucun mode global de réparation n'a été ajouté à l'audit.
6. **Secrets** : aucun nouveau secret ; vérifier les configurations SMTP et Google existantes sans exposer leurs valeurs.
7. **Audit distant** : lancer explicitement l'outil de lecture seule après autorisation opérationnelle ; les comptes historiques, projections absentes et liens contradictoires ne sont pas considérés réparés par la modification du code.

Les événements de parrainage historiques absents ne sont pas inventés rétroactivement. Un événement non résolu bloque le tirage ; après tirage final, le worker renvoie `manual_review_required`. Résoudre ces cas nécessite une revue individuelle, pas un changement silencieux des chances.

## F. Décisions métier et compatibilité

- Version minimale mobile, durée de coexistence et date de fermeture des prizes publics ; compatibilité de la console admin externe.
- Organisation de remise des lots plateforme ; identification et autorisations des partenaires. Aucun circuit partenaire implicite n'a été créé.
- Traitement des contradictions historiques et acceptations découvertes après tirage final.
- Éventuel refresh périodique Google : définir fraîcheur attendue, budget API et volume d'enseignes avant de choisir une fréquence. Seule la protection contre réponses désordonnées a été ajoutée.

## G. Commit

Travail exclusivement sur `develop`. Les commits locaux comprennent les corrections, tests et rapports. Aucun push ni modification de `main`. Le fichier préexistant non suivi `firebase/functions/rapport_repair.json` reste hors commit et n'a pas été modifié. Deux changements apparus pendant la validation dans `lib/components/merchant_offered_by_bubble.dart` et `lib/widgets/referral_game_card.dart` restent également hors commit.
