> **Historique de l’audit initial, avant correction B1/B2/B3.** Les constats de code et nombres de tests ci-dessous décrivent cet état antérieur. Pour l’état local actuel, les corrections, fichiers et verdicts, lire [le rapport de correction](compatibility-fixes-2026-09.md). Les procédures de déploiement restent non exécutées.

# Mise en production progressive C → B — préparation du 9 septembre 2026

**Aucun déploiement, changement de données Firebase distantes, backfill effectif, build publié, commit ou push n'a été exécuté dans cette préparation.** Les commandes de production ci-dessous sont un mode opératoire futur, conditionné à autorisation et aux critères de chaque phase. Ne pas les lancer en bloc.

## 1. Verdict et état de référence

**GO SOUS CONDITIONS pour engager séparément les vérifications et la phase indexes après autorisation. NO-GO pour déployer le backend métier complet, publier le nouveau mobile ou fermer les prizes maintenant.** Les tests positifs commerçant sont nécessaires mais ne lèvent pas les incompatibilités de schéma et de versions observées ci-dessous.

- Branche : `develop`.
- HEAD et référence locale `origin/develop` : `7520aa594d97c3294e343e79617a3a7c4b60a2c7`.
- Même SHA distant confirmé par `git ls-remote --heads origin refs/heads/develop`. La première tentative sandbox a échoué sur les credentials Windows ; la vérification en lecture seule hors sandbox a réussi.
- `main` : `48cd073eca1adaf8169218045abe5838494b1463`, non modifié.
- État initial : deux fichiers modifiés (`lib/components/merchant_offered_by_bubble.dart`, `lib/widgets/referral_game_card.dart`) et un non suivi (`firebase/functions/rapport_repair.json`). Ils ne sont ni écrasés, ni intégrés, ni lus pour cet audit.
- Modifications de cette préparation : ce document et trois fichiers de tests. Aucun fichier applicatif ni aucune rule n'a été modifié.
- Les 261 tests Functions, 81 tests Flutter et la compilation du chantier sont des résultats antérieurs. La validation ciblée ci-dessous les complète, sans prétendre avoir rejoué la totalité.

## 2. Bloquants découverts dans le code réel

| ID | Preuve | Conséquence et verrou |
|---|---|---|
| B1 | `PrizesRecord.fulfillmentType`, `lib/backend/schema/prizes_record.dart:54`, exige **owner ET enseigne** ; bouton dans `validation_lot_commercant_page_widget.dart:575` | Les rules acceptent historiquement owner **OU** enseigne, mais le nouveau mobile masque le bouton des lots avec une seule référence. Correction de compatibilité à préparer séparément, ou revue exhaustive des documents concernés avec décision explicite. Ne pas déclarer ces lots métier inutilisables par défaut. |
| B2 | `jeu_detail_commercant_page_widget.dart:1171`, requête game_id + owner_id | Un lot sans owner_id, mais rattaché à l'enseigne du commerçant, reste accessible depuis la recherche de l'accueil mais absent du détail du jeu. Cela arrive même avec lecture publique : le filtre exclut le document. Ajouter un fallback de liste fondé sur l'enseigne, ou traiter les données avec preuve d'appartenance avant GO. |
| B3 | Copie locale admin, `app/api/admin/marchands/route.ts:65` : owner est la **chaîne** `/users/uid`, owner_id est une référence | `merchant_games.js:12` cherche enseignes.owner == référence ; participation et tirage principal attendent aussi owner référence. Jeux absents du pager, participation refusée, ou tirage bloqué. Le test reproduit ce cas et retrouve le jeu avec owner référence. Vérification préalable de production obligatoire ; alignement de la console séparée nécessaire si cette route est utilisée. |
| B4 | `public_winners.js`, `prize_lot_snapshot.js`, métadonnées `__endpoint.eventTrigger.retry=false` | Les nouveaux triggers ne traitent pas automatiquement les documents historiques et n'ont pas de retry événementiel explicite. Un incident après création peut laisser projection/snapshot absent jusqu'à un nouvel événement ou une reprise ciblée. Indexes READY avant activation ; alertes et procédure de récupération indispensables. |
| B5 | `referral_reward_queue.js` et `registerReferralAcceptance` | Aucune transaction de déploiement entre producteur, worker et moteurs de tirage. L'ancien moteur peut ignorer les pending si déployé encore en parallèle. Préparer une fenêtre contrôlée, examiner les exécutions en cours et déployer les gardes avant le producteur. Aucun rollback vers un moteur ignorant les pending après leur introduction. |
| B6 | `firebase.rollout.json` pointe vers les rules transitoires ; diff des deux fichiers de rules | La transition ne conserve que la lecture publique des prizes. Toutes les nouvelles restrictions games/merchants/claim sont déjà présentes. Ce fichier n'est donc **pas** un rollback complet compatible avec toute ancienne app ou tout ancien schéma. |
| B7 | Archives du dépôt et tests des anciennes requêtes ; versions distribuées non inventoriées | Les anciens lecteurs game_id seul, claim_code seul et ticker prizes échouent avec les rules strictes. Impossible de garantir la compatibilité de versions réellement installées sans leurs numéros, builds et scénarios de recette. |

Autres limites : `getMerchantGames` accepte owner_id référence ou UID brut, pas toutes les chaînes `users/uid` ou `/users/uid`; les chemins de jeu/lot Flutter sont typés DocumentReference. Les `games` demeurent publics : les tests prouvent la séparation des listes personnelles et des droits d'édition, pas la confidentialité des documents game. Les règles de prizes ne prouvent pas la propriété par le seul game_id ; avoir un jeu n'autorise pas magiquement toute query de ses lots.

Ces constats rendent plus précise la note B du code : elle ne constituait pas une autorisation de migration sans contrôle des données historiques et des producteurs externes.

## 3. Tests positifs et négatifs — barrière obligatoire

Nouveau `firebase/functions/test/rollout_merchant_access.test.js` : mêmes scénarios sur rules strictes et transitoires, fixtures réinitialisées entre tests. Ajout de `rollout_owner_shape.test.js` pour le schéma réellement produit par la copie admin.

| Demande métier | Validation exécutée |
|---|---|
| 1. Le gagnant lit son lot | Lecture de sa collection my_lots, résolution prize_id, lecture du code autorisée |
| 2. Le propriétaire du jeu lit le lot gagné | Jeu créé par admin, prize.owner_id commerçant, lecture réussie |
| 3. Liste des lots commerçant | Vraies queries du détail game_id + owner_id, et accueil owner_id + enseigne_id, assertions sur les IDs retournés |
| 4. Validation légitime | claimed false → true permis, second retrait refusé ; anciens champs absents testés |
| 5. Autre commerçant refusé | Lecture de prize et queries d'un autre owner/enseigne refusées sous strict ; retrait et my_lots refusés dans les deux modes |
| 6. Jeu admin bien rattaché | Liste owner_id et lecture réussies, masquage métier autorisé au propriétaire, refusé à l'autre |
| 7. Compatibilité historique | Pas de fulfillment/deadline avec deux références : compatible ; owner seul/enseigne seule : rules compatibles, divergences UI consignées ; aucune des deux : gagnant autorisé, retrait commerçant refusé et revue requise |

Expiration, lot utilisé, plateforme, owner forgé, winner forgé, faux my_lots, accès anonyme et anciennes requêtes sont également couverts. Les lectures illégitimes de prizes **restent autorisées en transition par conception** : les tests n'en font pas un certificat de confidentialité. Sous strict, elles sont refusées.

Résultat : **57 tests Functions réussis, 0 échec, 0 ignoré**, dont 2 suites, en 11,8 s. Les fichiers exécutés sont indiqués ci-dessous. **3 tests Flutter ciblés réussis** : moderne/historique complet validable ; historique incomplet classé review par le code actuel ; plateforme/expiration/usage protégés. Les tests de caractérisation B1/B2/B3 verts constatent un problème de migration ; ils ne le transforment pas en comportement métier approuvé.

```powershell
# Uniquement avec Firestore Emulator local sur 127.0.0.1:8080.
node --test --test-concurrency=1 firebase/functions/test/rollout_merchant_access.test.js firebase/functions/test/rollout_owner_shape.test.js firebase/functions/test/firestore_rules_prizes_query_contract.test.js firebase/functions/test/firestore_rules_prizes_and_my_lots.test.js firebase/functions/test/public_winners_security.test.js firebase/functions/test/merchant_games.test.js firebase/functions/test/draw_indexes_contract.test.js
flutter test --no-pub test/rollout_prize_compatibility_test.dart
git diff --check
```

Firestore Emulator 1.21.0 du cache et Java 21 anglais utilisés ; aucun endpoint Firebase distant appelé par les tests. Un premier lancement du test Flutter a révélé un import relatif incompatible avec les imports absolus FlutterFlow ; l'import du test a été corrigé en `package:proxi_play/...`, puis les trois tests passent. Pas de changement de source pour faire passer le résultat métier.

**Aucun GO rules strictes si un test positif commerçant échoue.** Même lorsque cette barrière technique passe, exiger la recette des builds distribués et la résolution de B1/B2/B3.

## 4. Graphe de dépendances et mauvais ordres

Ordre requis : **inventaire des versions + audit des types propriétaires → indexes READY → backend et règles transitoires compatibles → vérification des données/projections → nouveau mobile → coexistence → rules strictes → contrôles continus**. L'audit initial est avancé avant les Functions pour détecter B3 ; un deuxième audit après backend vérifie les nouveaux objets.

| Déploiement isolé/inversé | Ce qui se passe réellement |
|---|---|
| Indexes seuls | Pas de changement de contrat mobile/rules ; coût et construction à surveiller. Ne pas supprimer d'index existant utilisé par un ancien client. |
| Functions seules | Admin SDK indépendant des rules ; APIs de participation restent additives. Mais indexes manquants font échouer des transactions/triggers ; B3 peut refuser participations/tirages. Les nouvelles projections ne seront pas lisibles par nouveau mobile si les rules en production ne les autorisent pas. |
| Rules strictes avant mobile | Listes historiques game_id seul/claim_code seul rejetées, ticker historique cassé ; ne pas déduire compatibilité des seules versions présentes dans Git. NO-GO. |
| Nouveau mobile avant Functions | `getMerchantGames` absent/mauvaise région : listes/agrégats commerçant en échec. Progression serveur absente : pas d'annonce de qualification. Projections absentes/interdites : gagnant animation/fallback ticker vides. my_lots sans snapshot conserve le fallback prize.get, mais ne garantit pas l'actualisation de la liste. |
| Ancien mobile après backend, avec rules transitoires | Lecture publique prizes conservée, contrat prize_id/my_lots conservé, progression serveur additive. Restent les changements d'ownership et de validation : B3 et refus de lots expirés/plateforme doivent être testés sur anciens builds. |
| Ancien mobile après strict | Certaines versions déjà migrées peuvent fonctionner ; celles aux anciennes queries ne le peuvent pas. Il n'existe pas d'exception sécurisée automatique fondée sur la version du client dans ces rules. Version minimale/coexistence à décider. |

`firebase.json` est la configuration canonique stricte, avec Functions et autres composants. `firebase.rollout.json` configure **uniquement** Firestore, en sélectionnant `firestore.legacy-prizes.rules` ; il ne publie ni Functions ni application. Ne jamais utiliser un `firebase deploy` sans `--only` dans cette migration.

### Lecteurs réels des prizes et projections

| Site | Données/query et effet des rules |
|---|---|
| `lib/pages/joueur/lots_joueur_page/...:63–80` | my_lots privé ; prize_snapshot s'il existe, sinon prize_id.get. Strict : le gagnant doit correspondre à winner_id référence. |
| `profil_joueur_page_widget.dart:60` | prize_id.get pour les compteurs ; mêmes droits gagnant. |
| `lot_detail_joueur_page_widget.dart` | Snapshot du seul prize ouvert, puis données game/enseigne ; strict nécessite bénéficiaire ou propriétaire/admin. |
| `home_commercant_page_widget.dart:80,94` | Deux queries owner_id référence puis enseigne_id référence, fusion, recherche locale du code. Ne pas réintroduire claim_code seul. |
| `jeu_detail_commercant_page_widget.dart:1171` | Query game_id + owner_id, reste autorisée sous strict ; voir B2 pour les documents exclus par son filtre. |
| `validation_lot_commercant_page_widget.dart:575` | Reçoit le prize sélectionné ; update claimed seulement, condition UI de fulfillment. Voir B1. |
| `global_ticker_service.dart:122,170` | D'abord stats/global ; fallback **public_prize_winners** trié win_date desc, limit 12. Plus de prize/profile read dans le fallback nouveau. Ancien fallback dépendait de prizes. |
| Animation détail et accueil joueur, lignes 1328/3343 | `animations/{id}/public_winner/current` ; ancien chemin privé winner/current conservé pour admin, public refusé. |
| `lib/backend/backend.dart`, `schema/prizes_record.dart` | Helpers génériques : liste/get/page, ne sont pas des appels autonomes. Aucun autre appel client direct trouvé dans lib. |
| `index.js` serveur | Statistiques ticker (`prizes` orderBy win_date), contact gagnant commerçant, rappels, backfill descriptif admin, notifyPrizeWon. Admin SDK, mais callables gardent leur propre contrôle d'autorisation. |
| Moteurs/réparations/public_winners/prize_lot_snapshot | Admin SDK en transactions ; indépendant de read public. Relecture actuelle pour éviter d'appliquer un ancien événement. |
| Scripts d'audit/réparation du dépôt | Admin SDK ; aucun n'a été exécuté à distance. Ne pas confondre script read-only et callable de réparation. |
| Console admin locale séparée | `lib/firebase/adminQueries.ts` lit des listes entières et par winner_id ; `merchantsQueries.ts:640` transforme une erreur de lecture prizes en snapshot vide. Un rôle admin mal reconnu peut donc apparaître comme « aucun lot » sans alerte. |

Les projections publiques ne contiennent ni claim_code ni UID/email/téléphone utilisateur. my_lots peut contenir un snapshot privé avec code : sa lecture reste réservée au joueur propriétaire. Un navigateur console utilisant le SDK client n'est pas Admin SDK et ne contourne pas les rules.

## 5. Indexes exacts du commit 7520aa5

Comparaison JSON effectuée avec `7520aa5^`, pas reprise d'une liste approximative : **3 composites nouveaux et 4 fieldOverrides nouveaux**. Tous les ordres ci-dessous sont ASC sauf mention contraire.

| Index ajouté | Portée / champs | Query réelle et composant | Si non prêt / ordre impératif |
|---|---|---|---|
| instant_winners | COLLECTION ; hasWinner, date | Participation : sous-collection du jeu, hasWinner == false, date <= now avec sélection du créneau dû | Participation pouvant échouer ; READY avant participateInGameTransaction. |
| referral_reward_pending | COLLECTION ; status, accepted_at | retryReferralRewards : status == pending, orderBy accepted_at, limit 200, pages | Queue non drainée ; READY avant worker et producteur. |
| referral_reward_pending | COLLECTION ; game_id, status | drawReferralGame : game_id == id, status in pending/manual_review_required | Tirage rejeté avant attribution ; READY avant cron/admin draw. |
| monthly_challenges.month | Champ simple COLLECTION_GROUP ASC ; garde aussi les indexes COLLECTION ASC/DESC | Stats/migration mensuelles : collectionGroup monthly_challenges, where month | Stats/upsert legacy en échec ; READY avant usages mensuels correspondants. |
| favorite_enseignes.enseigne_id | Champ simple COLLECTION_GROUP ASC ; garde COLLECTION ASC/DESC | index.js:908, notification nouveau jeu aux abonnés | Notifications absentes/échec ; READY avant ces usages, même s'ils ne sont pas nouveaux. |
| participants.user_id | Champ simple COLLECTION_GROUP ASC ; garde COLLECTION ASC/DESC | `joueur_admin_detail_page_widget.dart:49`, historique joueur admin ; fallback scan complet actuellement | Query filtrée échoue et fallback coûteux ; READY avant recette admin mobile. Pas une dépendance nouvelle d'un cron de tirage. |
| my_lots.prize_id | Champ simple COLLECTION_GROUP ASC ; garde COLLECTION ASC/DESC | checkAwardLinks et syncLotSnapshot : where prize_id == référence | Réparations, animation/referral/mensuel ou snapshot échouent ; READY avant ces Functions. |

Déjà présents avant 7520aa5 mais à vérifier en production : animations(status,end_date), games(hasWinner,end_date), referral_games(status,start_date), referral_games(status,end_date), prizes(game_id,owner_id), prizes(winner_id,win_date DESC). **L'index animation vient du commit parent 12bd6aa, pas de 7520aa5.** Le contrat ajouté vérifie les déclarations, pas leur état distant.

Autres queries : le pager commerçant combine une égalité et orderBy documentId, le ticker public orderBy win_date utilise l'index simple ; les égalités multiples du tirage principal (game_id/prize_type) et mensuel (month/status) peuvent utiliser la fusion des indexes simples. Vérifier les exemptions effectives et chaque query en recette. L'émulateur n'est pas une preuve de disponibilité des composites en production.

## 6. Functions à déployer, catégories et régions

Inventaire vérifié par les exports réels et leurs métadonnées locales `__endpoint`, sans appeler les handlers. Toutes sont Gen1. **us-central1** pour toutes les Functions ci-dessous, sauf `getMerchantGames` explicitement **europe-west1** ; absence de `.region()` signifie ici la région par défaut constatée. Ne déplacer aucune Function durant ce chantier.

A = compatible avec le protocole mobile existant ; B = doit précéder le nouveau mobile ; C = dépend d'indexes, d'autres Functions ou du schéma. Les catégories se recouvrent : A ne signifie pas « déployer maintenant ».

| Function exportée | Catégorie | Trigger/dépendance |
|---|---|---|
| refreshGooglePlaceRating | A | onWrite enseignes/{enseigneId}, secret GOOGLE_PLACES_API_KEY existant ; comparaison transactionnelle de place ID. Aucun cron périodique ajouté. |
| syncPublicPrizeWinner | A, B | **Nouvelle**, onWrite prizes ; projection publique minimale. Pas de reprise historique automatique ni retry explicite. Rules de projection avant son lecteur mobile. |
| syncPrizeLotSnapshot | A, B, C | **Nouvelle**, onWrite prizes ; index group my_lots ; modifie les liens existants cohérents, ne recrée pas les liens supprimés. |
| getMerchantGames | B, C | **Nouvelle**, callable europe-west1 ; enseignes.owner référence + game.owner_id/enseigne ; B3 à lever. Le mobile demande bien europe-west1. |
| participateInGameTransaction | A, B, C | Callable ; index instant_winners ; propriétaire fiable ; progression animation retournée et cache, fulfillment merchant. Pas de recomputation client legacy dans nouveau mobile. |
| generateInstantWinnersForGame | A, C | Callable ; remplace l'autorisation create_by par owner_id/fallback enseigne ; vérifier jeux créés par console admin. |
| notifyPrizeWon | A, C | onCreate prizes ; fallback propriétaire modifié, notification gagnant/commerçant ; SMTP/config existants. Ne pas redéclencher les créations pour « réparer » une projection. |
| pickMainPrizeWinners | A, C | Scheduler `0 0 * * *`, Europe/Paris ; indexes game, schéma enseigne ; attribution atomique et projection publique. |
| drawAnimationWinners | A, C | Scheduler minuit Paris ; index animations et group my_lots ; écrit gagnant privé + public en transaction. |
| adminRepairAnimationDraw | A, C | Callable ; mêmes gardes de cohérence et projection ; ne pas appeler dans ce plan. |
| drawReferralGameWinner | A, C | Scheduler minuit Paris ; status in active/ended et end_date <= now ; garde pending obligatoire. |
| adminDrawReferralGameWinner | A, C | Callable ; même moteur et garde pending, même si tirage anticipé admin. |
| adminRepairReferralGameDraw | A, C | Callable ; checkAwardLinks ; aucun bénéficiaire contradictoire réattribué. |
| adminReconcileReferralGameTickets | A, C | Callable ; helper addReferralGameTicket modifié pour interdire ajout après tirage final ; pas un audit read-only. |
| grantReferralReward | A, C | Callable admin ; existence/éligibilité parrain, refuse bonus classique pour événement mode game. |
| registerReferralAcceptance | A, C | Callable ; commit de l'événement pending avec acceptation ; nouvelle réponse conserve success/referralId ; worker/gardes prêts avant activation. |
| retryReferralRewards | A, C | **Nouvelle**, Scheduler every 1 minutes ; timeout 540 s ; pages 200 ; reprend pending, compte manuel explicite. Ne pas inventer de retry Scheduler rapide en supplément. |
| drawMonthlyChallengeWinner | A, C | Scheduler **01:00** Paris, `0 1 * * *` ; group my_lots et index/queries mensuelles ; journal de tirage. |
| adminRunMonthlyChallengeDraw | A, C | Callable ; même moteur mensuel renforcé. |
| adminRepairMissingMyLotsLink | A, C | Callable ; source/gagnant/canonique et group my_lots vérifiés ; manual_review_required exploitable côté console. |

Soit **20 exports nouveaux ou dont le comportement change**, dont 4 nouveaux (syncPublicPrizeWinner, syncPrizeLotSnapshot, getMerchantGames, retryReferralRewards). Les helpers `publicWinner`, `checkAwardLinks`, `drawMainPrize`, `processReferralReward` ne sont pas des noms déployables. `adminAuditMyLotsLinks`, les états/statistiques mensuels, le ticker global, autoManageReferralGames et les autres exports inchangés n'ont pas besoin d'être redéployés pour simplement créer leurs indexes. Un déploiement sélectif embarque les modules requis par les Functions sélectionnées ; compiler le bundle TypeScript avant.

Scheduler/PubSub : inspecter les jobs existants et leur région via la liste, ne pas déduire aveuglément leur ID de leur nom d'export. Les métadonnées n'activent aucun retry explicite des quatre crons ; remonter l'erreur rend l'échec visible mais **ne prouve pas une relance automatique immédiate**. Le worker referral, lui, est réinvoqué chaque minute. Les nouvelles Functions Firestore exposent retry=false : mettre en place alertes et reprise ciblée avant GO.

## 7. Console admin séparée — contrôle obligatoire

Une copie est accessible en lecture seule dans `C:\dev\PROXIPLAY\admin-proxiplay` (AGENTS.md lu ; aucun changement effectué). Sa version déployée n'est pas connue ; ne pas assimiler copie locale et production.

- [ ] Auth navigateur : token ou profil admin réellement reconnu par isAdmin ; vérifier renouvellement du token et SDK utilisé. Admin SDK sur route serveur != SDK client dans adminQueries.
- [ ] Lecture exhaustive prizes et queries winner_id : erreurs visibles, pas listes vides silencieuses. `merchantsQueries.ts:640` contient actuellement `.catch(() => emptySnapshot)`.
- [ ] Création enseigne : `app/api/admin/marchands/route.ts:65–73` écrit owner chaîne et owner_id référence. Alignement de contrat à traiter dans ce dépôt séparé avant activation du backend strict sur la propriété.
- [ ] Création/duplication jeu : `lib/firebase/gamesQueries.ts:558,773` écrit create_by propriétaire et enseigne_id, sans owner_id de jeu explicite dans ces payloads. `app/admin/campaigns/page.tsx:1407` utilise aussi create_by propriétaire. Cela marche seulement si le fallback enseigne est normalisé. Préserver create_by comme audit et définir le propriétaire fonctionnel explicitement.
- [ ] Formats enseigne_id : si la console sélectionne collection merchants, un merchantRef peut ne pas pointer vers enseignes ; les moteurs Flutter/Functions attendent enseignes. Ne pas migrer de référence sans examiner la source.
- [ ] Queries de visibilité : `adminQueries.ts:1029` utilise encore create_by ; tester admin créateur distinct du propriétaire, plusieurs enseignes et plus de 15 jeux.
- [ ] Validation claimed : merchant autorisé sur lot disponible ; plateforme/partner admin uniquement ; comprendre claimed_at/status legacy vs champ canonique claimed. Ne pas accepter la seule réussite HTTP d'un callable si son statut est manual_review_required.
- [ ] Gagnant animation privé : accès admin prévu ; ne pas réutiliser son contenu pour les pages publiques.
- [ ] Jeu classique et legacy jeux : isAdmin et UID fiables ; pas de relation propriétaire contrôlée par email.
- [ ] Recette croisée : création admin → jeu visible commerçant → participation → lot visible au gagnant et au commerçant → retrait autorisé → autre commerçant refusé.

## 8. Données historiques : préparation exclusivement read-only / dry-run

Commandes futures depuis la racine du dépôt, avec credentials opérateur en **lecture seule** lorsque possible. Identifiants ciblés choisis dans l'audit ; aucune commande d'application de backfill n'est fournie.

```powershell
$RolloutProject = 'proxi-play-odzp2e'
if ($env:FIRESTORE_EMULATOR_HOST -or $env:FIREBASE_AUTH_EMULATOR_HOST) { throw 'Séparer le terminal de recette locale du terminal de lecture production.' }
node firebase/functions/scripts/audit_game_integrity.js "--project=$RolloutProject" > .tmp_prod_integrity.json
$audit = Get-Content -Raw .tmp_prod_integrity.json | ConvertFrom-Json
$audit.findings | Group-Object kind | Select-Object Name,Count
# IDs explicitement choisis par l'opérateur après lecture de l'audit :
$AnimationId = Read-Host 'ID animation à vérifier'
node firebase/functions/scripts/backfill_public_winners.js "--project=$RolloutProject" --type=animation "--id=$AnimationId"
$PrizeId = Read-Host 'ID prize à vérifier'
node firebase/functions/scripts/backfill_public_winners.js "--project=$RolloutProject" --type=prize "--id=$PrizeId"
```

Le script de projections est **dry-run par défaut** ; il lit les documents dans une transaction et ne les écrit pas dans ces commandes. Ne pas appeler un callable de réparation pour réaliser un audit. `audit_game_integrity.js` pagine 250 docs mais les conserve en mémoire ; snapshot non atomique, budget de lectures et volume à estimer. Il scanne prizes, my_lots, games, animations, referral_games, monthly_challenge_draws, users, enseignes, public_winner, referrals et pending ; il ne liste pas globalement les public_prize_winners, ne contrôle pas toutes les configurations mensuelles, et ne détecte pas exhaustivement les champs owner au mauvais type. Compléter les résultats par une inspection ciblée des types sans les modifier.

| Anomalie | Traitement envisageable après autorisation distincte |
|---|---|
| Projection prize/animation absente, gagnant/source cohérents | Backfill ciblé create-only disponible, dry-run préalable ; aucune nouvelle attribution. |
| Projection existante mais obsolète | Le backfill create-only ne la corrige pas ; revue ciblée, ne pas supprimer pour forcer un effet. |
| my_lots manquant, utilisateur/source/gagnant cohérents, pas de conflit | Réparation additive ciblée possible via fonction gardée ; jamais globale ni exécutée ici. |
| my_lots d'un autre owner, doublon ou canonique contradictoire | manual_review_required ; ne pas fusionner/supprimer/réattribuer automatiquement. |
| Snapshot my_lots absent | Lecture prize.get conservée ; pas de commande de backfill snapshot dédiée. Préparer une reprise ciblée sans recréer le lien si nécessaire. |
| Utilisateur inexistant / winner-source contradictoires | Revue manuelle ; ne pas recréer un compte ou choisir un autre gagnant automatiquement. |
| Acceptance avec pending avant tirage | Worker idempotent peut résoudre le ticket si admissible ; inspecter statut final et logs. |
| Acceptance ancienne sans événement, après tirage ou plusieurs jeux possibles | Ne pas inventer une affectation rétroactive ; revue métier obligatoire. |
| owner chaîne, owner_id absent/contradictoire, enseigne legacy | Corriger le contrat seulement après preuve UID/propriété et alignement du producteur admin ; B3 non couvert par une réparation existante sûre. |
| Lot merchant sans owner/enseigne | Revue du circuit ; B1/B2 empêchent de déclarer la compatibilité mobile acquise. |
| Lot platform avec owner marchand / partner sans partenaire explicite | Revue métier, pas de validation commerçant automatique. |
| Tirage fini sans gain/projection | Distinguer fin sans éligible, gain manquant et simple affichage ; jamais relancer la sélection comme réparation. |

## 9. Checklist opérationnelle par phase

Les aides locales de `gcloud firestore indexes composite list`, `indexes fields list` et `scheduler jobs list` ont été vérifiées ; les autres commandes ci-dessous sont préparées pour l'opérateur, non exécutées à distance. Ne pas inscrire un secret dans le rapport. Utiliser un compte habilité et un terminal distinct des émulateurs.

### PHASE 0 — sauvegardes, état réel, recette et schémas

**Prérequis :** autorisation de lecture production ; référence Git ci-dessus ; accès à la version admin et aux builds réellement distribués. **Composants :** configuration projet, jobs, propriétaires, versions.

```powershell
git branch --show-current
git rev-parse HEAD origin/develop
git status --short
$RolloutProject = 'proxi-play-odzp2e'
firebase functions:list --project $RolloutProject
firebase firestore:indexes --project $RolloutProject
gcloud firestore databases describe --database='(default)' --project=$RolloutProject --format=json
gcloud scheduler jobs list --location=us-central1 --project=$RolloutProject --format=json
gcloud scheduler jobs list --location=europe-west1 --project=$RolloutProject --format=json
```

- [ ] Archiver les rules effectivement publiées et leurs identifiants de release, configuration/indexes et versions Functions ; ces fichiers Git ne prouvent pas l'état publié.
- [ ] Vérifier sauvegarde/PITR disponible et procédure de restauration ciblée. Une restauration globale de base écraserait des gains créés pendant la migration : ce n'est pas le rollback de ce plan. Une nouvelle sauvegarde/export nécessite autorisation distincte, aucune commande d'écriture de sauvegarde n'est exécutée ici.
- [ ] Exécuter l'audit read-only de la section 8 **avant** backend pour rechercher B3 et les lots historiques ; compléter types owner et variantes owner_id.
- [ ] Exécuter les tests locaux et les sept parcours dans une recette isolée sur ancien/nouveau mobile et console admin. Pas de retrait réel de lot de production pour « tester ».

**GO :** projet confirmé, accès/rôles et versions inventoriés, schémas compatibles démontrés ou correctifs séparés validés, sauvegarde connue. **NO-GO :** propriété chaîne non traitée, version admin inconnue, anciens clients non inventoriés, un accès métier positif en échec. **Rollback :** rien à annuler dans cette phase read-only ; conserver preuves locales et suspendre la suite.

### PHASE 1 — indexes, sans activation métier

**Prérequis :** autorisation explicite de déployer les indexes seulement ; comparaison aux indexes réellement présents, pas de suppression imposée. **Composants :** les 7 déclarations nouvelles et indexes déjà requis.

```powershell
# FUTUR DÉPLOIEMENT, ne pas exécuter dans cette préparation.
firebase deploy --only firestore:indexes --config firebase.json --project $RolloutProject
# Contrôles read-only :
gcloud firestore indexes composite list --database='(default)' --project=$RolloutProject --format=json
foreach ($group in @('monthly_challenges','favorite_enseignes','participants','my_lots')) {
  gcloud firestore indexes fields list --collection-group=$group --database='(default)' --project=$RolloutProject --format=json
}
```

**GO :** tous les indexes requis par la prochaine Function sont READY, pas simplement déclarés ou CREATING ; queries de recette exactes réussies. **NO-GO :** erreurs de construction/exemptions non comprises, demande de suppression d'index utile aux anciens clients. **Rollback :** laisser les indexes additifs en place et différer le backend ; ne pas supprimer un index pour tenter de réparer une query en échec.

### PHASE 2 — backend et rules transitoires compatibles

**Prérequis :** B3 levé, phase 1 validée, fenêtre maîtrisée pour les tirages, suivi de queue et alertes. Les anciens contrats de création/édition doivent passer sous le fichier transitoire. **Composants :** les 20 Functions de la section 6 et rules transitoires.

Avant les commandes de tirage, l'opérateur relève dans la liste Scheduler les IDs réels, la région et les exécutions en cours ; aucun job ne doit être interrompu après avoir commencé à attribuer un gain. Pour la fenêtre, commandes futures ciblées uniquement après choix explicite :

```powershell
$DrawJob = Read-Host 'ID exact du job de tirage à mettre en pause'
$DrawLocation = Read-Host 'Région Scheduler exacte de ce job'
gcloud scheduler jobs pause $DrawJob --location=$DrawLocation --project=$RolloutProject
# Compiler localement le bundle :
Push-Location firebase/functions
node node_modules/typescript/bin/tsc
Pop-Location
# 2A : triggers auxiliaires, pager et Google, après prérequis de schéma/index.
firebase deploy --only 'functions:syncPublicPrizeWinner,functions:syncPrizeLotSnapshot,functions:getMerchantGames,functions:refreshGooglePlaceRating' --project $RolloutProject
# 2B : gardes de tirage et réparation AVANT producteur de pending.
firebase deploy --only 'functions:pickMainPrizeWinners,functions:drawAnimationWinners,functions:adminRepairAnimationDraw,functions:drawReferralGameWinner,functions:adminDrawReferralGameWinner,functions:adminRepairReferralGameDraw,functions:drawMonthlyChallengeWinner,functions:adminRunMonthlyChallengeDraw,functions:adminRepairMissingMyLotsLink,functions:adminReconcileReferralGameTickets' --project $RolloutProject
# 2C : worker/bonus avant acceptation ; tester et vérifier le job chaque minute.
firebase deploy --only 'functions:retryReferralRewards,functions:grantReferralReward' --project $RolloutProject
firebase deploy --only 'functions:registerReferralAcceptance,functions:participateInGameTransaction,functions:generateInstantWinnersForGame,functions:notifyPrizeWon' --project $RolloutProject
# 2D : accès projections + durcissements compatibles, lecture prizes encore publique.
firebase deploy --only firestore:rules --config firebase.rollout.json --project $RolloutProject
```

Les pauses ne sont pas une protection contre les callables de tirage manuel : désigner l'opérateur et interdire ces actions dans la fenêtre. Un déploiement peut recréer/réactiver un job : relire son état après chaque sous-phase ; ne pas supposer qu'une pause reste effective. Chaque étape doit être observée avant la suivante.

**GO :** exports/régions présents, anciennes et nouvelles requêtes métier autorisées, queue drainée sans doublon en recette, logs visibles, projections lisibles, aucun champ privé dans projections. **NO-GO :** n'importe quel échec commerçant, erreur index, pending sans worker, job ancien encore susceptible d'ignorer pending, jeu admin absent. **Rollback :** voir section 10 ; ne pas revenir à l'ancien moteur referral après création d'événements. Ne pas déployer le SHA parent globalement.

### PHASE 3 — audit read-only après backend

**Prérequis :** phase 2 sous contrôle, opérateur de lecture. **Composants :** nouvelles créations prize/my_lots/projections et queue.

```powershell
node firebase/functions/scripts/audit_game_integrity.js "--project=$RolloutProject" > .tmp_prod_integrity_after_backend.json
firebase functions:log --only syncPublicPrizeWinner,syncPrizeLotSnapshot,retryReferralRewards,drawReferralGameWinner --project $RolloutProject
```

**Contrôles :** comparer les findings par ID et type, confirmer les nouveaux objets sans modifier ceux de production ; les logs peuvent contenir des informations opérationnelles, conserver l'accès restreint. **GO :** pas de nouvelle incohérence, triggers actifs, visibilité des lots conservée dans recette, pas de pending ancien inexpliqué. **NO-GO :** accroissement des orphelins, snapshots/projections absents après événements, backlog ou erreur masquée. **Rollback :** différer mobile/strict, garder les documents, corriger le traitement ciblé.

### PHASE 4 — projections/backfills ciblés éventuels

**Prérequis :** liste revue par l'opérateur et politique de confidentialité ; aucune nouvelle sélection de gagnant. **Composants :** projections, éventuellement liens canoniques après validation distincte.

Commandes autorisées dans le plan préparatoire : uniquement les deux dry-runs de la section 8, avec un ID à la fois. **Aucune commande d'application n'est fournie.** Les outils de réparation/callables doivent faire l'objet d'une autorisation ultérieure portant sur des cibles concrètes.

**GO :** sources cohérentes, dry-run `would_publish`, confirmation que les projections utiles au mobile existent après opération ultérieure autorisée. **NO-GO :** manual_review_required, compte absent, source contradictoire, tentative de modifier un bénéficiaire pour rendre le lot visible. **Rollback :** pas d'écriture à annuler pour un dry-run ; pour une future projection erronée, traiter seulement la projection après revue, jamais prize/winner ni les chances du tirage.

### PHASE 5 — nouvelle version mobile

**Prérequis :** B1/B2 résolus ou couverture historique démontrée avec décision métier explicite ; B3 levé ; backend, région europe-west1 et rules transitoires prêts ; projections utiles présentes.

```powershell
flutter test --no-pub
flutter analyze --no-pub
# Build local futur, numéro/version décidés par le responsable release :
$MobileVersion = Read-Host 'Version approuvée'
$MobileBuild = Read-Host 'Numéro de build approuvé'
flutter build appbundle --release --build-name=$MobileVersion --build-number=$MobileBuild
# Sur le poste macOS de release iOS, pas sur ce poste Windows :
# flutter build ipa --release --build-name=VERSION_APPROUVEE --build-number=BUILD_APPROUVE
```

**Contrôles :** qualification server-only et rejeu sans doublon, gagnant animation public, ticker stats puis fallback projection, pagination >15 pour jeu admin, lots modernes et historiques, claimed/expiration, accès refusé à l'autre commerçant. Snapshot my_lots est une optimisation additive ; l'absence de snapshot doit continuer à lire le prize. **GO :** tous ces parcours positifs et négatifs passent sur les deux plateformes. **NO-GO :** bouton de retrait historique absent, lots omis du détail, mauvais endpoint pager, dépendance seulement supposée déployée. **Rollback :** arrêter diffusion ; conserver les endpoints requis par les versions déjà distribuées, pas de rollback serveur les supprimant. Publication stores nécessite une décision ultérieure, aucune commande de publication ici.

### PHASE 6 — coexistence

**Prérequis :** build en diffusion contrôlée après autorisation. **Composants :** anciennes/nouvelles apps, admin, règles transitoires.

Commandes : mêmes lectures `firebase functions:list`, `functions:log` et audit de phase 3 ; aucune nouvelle mutation nécessaire. Faire un suivi réel des versions actives via les outils de release existants, sans inventer un pourcentage ou une durée fixe.

**GO vers strict :** version minimale décidée, lecteurs legacy retirés ou support explicitement arrêté, console admin validée, tests positifs commerçant en recette strict tous verts, B1/B2/B3 levés, projections utiles disponibles. **NO-GO :** ancien lecteur encore requis ou visibilité marchand non démontrée. **Rollback :** prolonger coexistence et conserver lecture publique temporaire ; ce maintien conserve le risque de confidentialité et requiert un responsable et une échéance, pas une acceptation implicite permanente.

### PHASE 7 — fermeture stricte des prizes

**Prérequis :** toutes les barrières de phase 6 et autorisation explicite ; sauvegarde du ruleset transitoire effectivement publié ; opérateur prêt à rétablir l'accès métier.

```powershell
# FUTUR, actuellement NO-GO.
firebase deploy --only firestore:rules --config firebase.json --project $RolloutProject
```

**Contrôles immédiats :** les sept scénarios de la section 3, surtout les **listes** de lots et le retrait légitime ; anonyme/autre marchand refusés ; admin liste complète ; projection publique autorisée. **GO :** accès métier préservé et accès illégitime refusé sur les clients supportés. **NO-GO :** « zéro lot » ou erreur de permissions côté commerçant, même si lecture isolée et tests négatifs passent. **Rollback :** rétablir uniquement le ruleset transitoire testé avec la commande de section 10 ; ne jamais réattribuer/recréer des lots pour contourner une erreur de permission.

### PHASE 8 — contrôles post-déploiement

**Prérequis :** suivi opérationnel continu, pas seulement compilation/fin de commande deploy. **Composants :** quatre tirages, worker, snapshots, projections, Google, mobile et admin.

```powershell
firebase functions:log --only pickMainPrizeWinners,drawAnimationWinners,drawReferralGameWinner,drawMonthlyChallengeWinner,retryReferralRewards --project $RolloutProject
gcloud scheduler jobs list --location=us-central1 --project=$RolloutProject --format=json
node firebase/functions/scripts/audit_game_integrity.js "--project=$RolloutProject" > .tmp_prod_integrity_after_strict.json
# Reprendre chaque job uniquement après validation du moteur/gardes et revue des jobs :
gcloud scheduler jobs resume $DrawJob --location=$DrawLocation --project=$RolloutProject
```

**GO final :** au moins une exécution opérationnelle observée des crons concernés selon leurs horaires, pas d'erreur initiale absorbée, attribution unique, pas de ticket rétroactif, gain réellement visible aux deux acteurs légitimes. **NO-GO :** logs seuls sans preuve de résultat métier, accumulation pending/manual sans traitement, projection manquante. **Rollback :** pause des opérations d'attribution touchées, investigation ciblée, conservation des gains et files ; pas de restauration globale silencieuse.

## 10. Rollback par incident

| Incident | Réponse préparée ; opérations futures uniquement |
|---|---|
| Rules strictes trop restrictives | `firebase deploy --only firestore:rules --config firebase.rollout.json --project $RolloutProject` après accord opérateur. Rouvre prizes mais garde les autres durcissements. Si le problème porte sur games/owner, ce rollback ne suffit pas : corriger le contrat ou restaurer un ruleset de secours explicitement testé, pas toute la base. |
| Index manquant/non READY | Ne pas activer sa Function ; si déjà active, suspendre le job d'attribution touché et attendre l'index. Ne pas supprimer la queue ; une erreur trigger n'est pas forcément rejouée automatiquement. |
| Function auxiliaire incompatible | Déploiement sélectif d'une version compatible revue, conserver nouveaux champs/documents. Pas de commande globale de rollback au commit parent, car les clients déjà diffusés en dépendent. |
| Mobile déjà diffusé | Arrêter la diffusion et publier un correctif ultérieurement ; maintenir getMerchantGames/projections/réponse animation. La suppression d'un endpoint ne désinstalle pas l'app. |
| Projection absente | Garder accès métier aux prizes, vérifier trigger/index, dry-run ciblé ; ne pas rejouer un tirage pour reconstruire son affichage. |
| Problème referral | Garder pending et les gardes de clôture, suspendre seulement les tirages concernés ; corriger worker puis reprendre. Ne jamais supprimer pending pour débloquer le tirage, ni ajouter un ticket après attribution finale. |
| Problème animation | Conserver gagnant privé/prize/my_lots ; réparer uniquement projection/lien après contrôle, jamais désigner un nouveau gagnant. |
| Lot historique invisible | Distinguer permission refusée, filtre qui omet et bouton qui masque ; B1/B2 sont distincts. Un retour aux rules publiques ne change pas le filtre owner_id ni le getter Flutter. |

## 11. Décisions humaines restantes et arrêt

1. Autoriser une première phase précise ; ce document n'autorise aucun déploiement.
2. Choisir la compatibilité des historiques à une seule référence et corriger B1/B2 sans réouvrir d'accès illégitime.
3. Aligner le contrat owner de la console admin et vérifier les documents réellement créés par cette version ; aucun changement effectué dans ce dépôt séparé.
4. Décider versions minimales, période de coexistence, seuil d'arrêt des anciennes apps et responsabilité de fermeture du P0 public.
5. Valider les cibles de backfill et les cas manual_review_required, jamais une réparation globale.
6. Définir circuit plateforme/partenaires, budgets de lecture, alertes et procédure de reprise des triggers sans retry.

**Arrêt avant production.** Les tests positifs commerçant passent au niveau des rules pour les schémas canoniques et leur fallback documenté ; le plan complet reste bloqué par les incompatibilités reproduites et l'état de production non inspecté. Aucun commit/push sans demande ultérieure.
