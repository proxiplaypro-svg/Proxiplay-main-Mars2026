# Corrections locales de compatibilité C → B — 9 septembre 2026

Ce rapport remplace les constats B1/B2/B3 du plan initial pour l'état local corrigé. Aucun déploiement, accès aux données Firebase de production, apply, commit ou push. Le dépôt mobile reste sur `develop`. La copie admin est restée sur sa branche initiale `wip/commercant-du-mois` ; aucune branche `main` modifiée.

## Les trois incompatibilités

1. **Bouton historique corrigé.** `PrizesRecord.fulfillmentType` exigeait `ownerId != null && enseigneId != null`. Une seule relation valide suffit désormais. `canBeClaimedBy` contrôle disponibilité, routage marchand et propriétaire prioritaire ; seul un lot sans propriétaire explicite bénéficie du fallback enseigne. La validation relit le lot en transaction, vérifie que le bénéficiaire n'a pas changé et applique seulement `claimed: true`. Les rules recontrôlent droits, expiration et transition atomique. Un historique sans `claimed` est explicitement considéré non réclamé, sans assouplir la propriété. Plateforme, partenaire, expiré et déjà utilisé restent non validables par le commerçant.

2. **Liste du détail corrigée.** L'ancien filtre `game_id + owner_id` excluait les historiques enseigne seule. La callable `getMerchantPrizes` pagine les candidats, filtre côté serveur et retourne uniquement les IDs autorisés. Flutter lit chaque document sous les rules ; la recherche de code à l'accueil utilise le même service, sans limite silencieuse à 200. Les curseurs avancent aussi sur les pages filtrées vides. La propriété du jeu suit celle du pager commerçant : créateur admin sans effet, propriétaire explicite prioritaire, enseigne rattachée vérifiée. Le détail se rafraîchit après validation et propose « Actualiser les lots » pour les gains arrivés pendant son ouverture ; il ne possède plus de flux temps réel de liste.

   Les rules strictes distinguent `get` (fallback historique autorisé) et `list` (propriétaire/gagnant explicite ou admin). L'ancienne requête large par enseigne est refusée ; cela évite de laisser une branche de requête contourner la priorité du propriétaire. Les tests exécutent le chemin complet utilisé par le mobile : pagination serveur, lecture individuelle sous rules strictes, validation légitime. Le endpoint de coordonnées gagnant applique la même priorité et ne divulgue pas les coordonnées au propriétaire de l'enseigne lorsqu'un autre propriétaire est explicite sur le lot.

3. **Type admin corrigé.** Deux écritures de `owner` trouvées dans les sources admin : création de commerçant (`app/api/admin/marchands/route.ts`) et édition (`app/admin/commercants/[merchantId]/edit/page.tsx`). Toutes deux écrivent maintenant des références `users/uid`, comme `owner_id`. L'édition conserve la suppression des deux champs lorsqu'aucun propriétaire n'est renseigné. Les occurrences dans `adminQueries.ts` sont des lectures/valeurs d'affichage, conservées compatibles.

   Backend : un helper commun accepte référence, UID, `users/uid`, `/users/uid` pour les anciennes enseignes. Deux champs contradictoires ou malformés échouent de manière restrictive. Pager des jeux, participation et tirage principal, recherche de lots et lecture des coordonnées utilisent ce contrat. Les nouveaux lots restent produits avec `owner_id` référence. Flutter sait aussi lire les enseignes historiques dont `owner` était une chaîne. Aucune propriété n'est déduite de l'email ou du créateur admin.

## Validation locale

Les résultats finaux sont consignés ci-dessous après exécution. Les émulateurs utilisent exclusivement des projets `demo-*`. Les tests de notifications substituent Nodemailer et n'envoient pas de mail.

- Les tests couvrent gagnant et lien `my_lots`, commerçant propriétaire, listes modernes/historiques mélangées, admin créateur, retrait légitime, autre commerçant et mauvais bénéficiaire refusés, propriétaires contradictoires, champs historiques absents, expiration et plateforme.
- Le tirage sur enseigne historique admin produit un lot avec propriétaire référence et un lien `my_lots` ; la participation historique réussit et un propriétaire contradictoire est refusé avant consommation d'une partie.
- Les tests de rules sont exécutés sur les variantes stricte et transitoire. **La lecture des lots reste publique dans la variante transitoire** : le refus d'une lecture illégitime est garanti par la variante stricte ; la validation illégitime est refusée dans les deux variantes.
- Les tests historiques de requêtes sont conservés comme preuve des limites des anciens clients. Les nouveaux tests `merchant_prizes.test.js` valident leur remplacement métier, y compris les documents manquants auparavant.
- TypeScript Functions : contrôle sans émission réussi. Contrat admin : 2 tests réussis. TypeScript des sources admin sans cache `.next` : 0 diagnostic. Le `tsc` admin global échoue sur 4 références générées périmées aux routes `vip-qr` et `vip-campaigns` ; aucune erreur dans les sources modifiées, cache non altéré.

## Historique et migration

`firebase/functions/scripts/audit_owner_compatibility.js` est un **audit hors ligne sans mode apply**. Il prend un export JSON local d'enseignes sous forme de tableau `{id, owner, owner_id}` ; représenter les références par `{ "path": "users/uid" }`. Il classe les entrées `canonical`, `compatible_normalization` ou `manual_review` et propose seulement un chemin canonique.

Exécution future sur un export local autorisé :

```text
node firebase/functions/scripts/audit_owner_compatibility.js chemin/export-local.json
```

La normalisation des chaînes cohérentes n'est plus un préalable bloquant pour ces parcours corrigés. Les documents sans relation de propriété, malformés ou contradictoires exigent toujours une revue avec preuve métier ; aucun propriétaire n'est choisi automatiquement. L'exhaustivité des données de production n'a pas été auditée dans ce chantier. Les anciennes projections `public_prize_winners` et snapshots `my_lots`, ainsi que les autres points B4–B7 du plan, gardent leurs contrôles historiques séparés. Aucun backfill n'a été appliqué.

## Appréciation de mise en production

| Élément | Avis | Conditions restantes |
|---|---|---|
| Indexes | GO SOUS CONDITIONS | Contrat local testé ; contrôler les indexes READY dans l'environnement cible avant activation des fonctions. Aucune nouvelle définition d'index composite nécessaire au nouveau pager. |
| Backend compatible | GO SOUS CONDITIONS | Corrections locales et tests métier verts ; livrer `getMerchantPrizes` avant le mobile et respecter l'ordre de migration des producteurs/workers du plan. Audit des incohérences historiques et surveillance des projections. |
| Mobile | GO SOUS CONDITIONS | Dépend de la nouvelle callable dans `europe-west1`. Recette sur appareils et environnement de validation, notamment recherche de code et actualisation des lots. Analyse sans erreur, dette de warnings existante. |
| Rules transitoires | GO SOUS CONDITIONS | Accès métier testés ; lecture publique des lots toujours présente. Phase temporaire uniquement, pas une garantie de confidentialité ni un rollback de toutes les anciennes écritures. |
| Rules strictes | NO-GO pour déploiement immédiat | Tests positifs commerçant et refus illégitimes passent localement, mais inventaire/migration des versions mobiles distribuées, backend disponible, projections historiques et recette réelle restent requis. Les anciens clients par enseigne seule ne sont pas compatibles. |

## Fichiers du chantier

La liste finale ci-dessous exclut volontairement les trois fichiers préexistants protégés : `firebase/functions/rapport_repair.json`, `lib/components/merchant_offered_by_bubble.dart`, `lib/widgets/referral_game_card.dart`. Ils n'ont pas été modifiés par cette correction.

- `docs/compatibility-fixes-2026-09.md`
- `docs/prod-rollout-2026-09.md`
- `firebase/firestore.legacy-prizes.rules`
- `firebase/firestore.rules`
- `firebase/functions/index.js`
- `firebase/functions/main_prize_draw.js`
- `firebase/functions/merchant_games.js`
- `firebase/functions/merchant_ownership.js`
- `firebase/functions/merchant_prizes.js`
- `firebase/functions/participate_in_game_transaction.js`
- `firebase/functions/scripts/audit_owner_compatibility.js`
- `firebase/functions/test/firestore_rules_prizes_and_my_lots.test.js`
- `firebase/functions/test/firestore_rules_prizes_query_contract.test.js`
- `firebase/functions/test/get_prize_winner_contact_for_merchant.test.js`
- `firebase/functions/test/merchant_ownership.test.js`
- `firebase/functions/test/merchant_prizes.test.js`
- `firebase/functions/test/participate_already_played_no_parts.test.js`
- `firebase/functions/test/rollout_merchant_access.test.js`
- `firebase/functions/test/rollout_owner_shape.test.js`
- `lib/backend/schema/enseignes_record.dart`
- `lib/backend/schema/prizes_record.dart`
- `lib/pages/commercant/home_commercant_page/home_commercant_page_widget.dart`
- `lib/pages/commercant/jeu_detail_commercant_page/jeu_detail_commercant_page_widget.dart`
- `lib/pages/commercant/validation_lot_commercant_page/validation_lot_commercant_page_widget.dart`
- `lib/services/merchant_prizes_service.dart`
- `test/rollout_prize_compatibility_test.dart`

Copie admin locale (C:/dev/PROXIPLAY/admin-proxiplay) :

- app/api/admin/marchands/route.ts
- app/admin/commercants/[merchantId]/edit/page.tsx
- owner-contract.test.cjs

## Résultats finaux exécutés

| Vérification | Résultat |
|---|---|
| Functions ciblées propriété/listes/rules/pager jeux | 55/55 au premier passage ciblé ; cas supplémentaires inclus ensuite |
| Suite Functions utile, séquentielle, hors test SMTP substitué | 298/298, 0 échec, 0 ignoré, environ 146 s |
| Coordonnées gagnant et ancien contrat de requêtes après dernière correction | 9/9 |
| Notifications idempotentes, Nodemailer substitué | 2/2 |
| Flutter ciblé compatibilité | 5/5 |
| Suite Flutter complète finale | 86/86 |
| flutter analyze --no-pub | 0 erreur, 24 warnings, 166 infos ; code retour 1 en raison des diagnostics existants |
| TypeScript Functions --noEmit | Réussi |
| Contrat admin | 2/2 |
| TypeScript admin sources hors cache généré | 0 diagnostic |
| TypeScript admin global | 4 erreurs TS2307 dans .next généré : routes vip-qr / vip-campaigns absentes |
| git diff --check (mobile et admin) | Réussi |

La suite Functions a été exécutée avec FIRESTORE_EMULATOR_HOST=127.0.0.1:8080, FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 et FUNCTIONS_EMULATOR=true, via node --test --test-concurrency=1 sur tous les fichiers test/*.test.js sauf notify_prize_won_idempotence.test.js. Ce dernier a été lancé séparément, sans FUNCTIONS_EMULATOR, avec transport SMTP substitué. Les essais parallèles précédents de certains anciens tests ont révélé une interférence de leurs fixtures ; l'exécution finale séquentielle évite ce partage concurrent.

Les validations ne constituent pas une recette appareil ni une vérification de l'état des indexes distants. Aucun des trois fichiers protégés n'est inclus dans cette liste de corrections.
