# Vérification du code gagnant — correctif et audit du 25 septembre 2026

1. **Flutter concerné** : `HomeCommercantPageWidget`, nouvelle méthode
   `_checkWinningCode`, puis `_findPrizeForMerchantClaimCode` et
   `loadMerchantPrizes`. Le résultat valide ouvre toujours
   `ValidationLotCommercantPageWidget`, avec confirmation de remise distincte.

2. **Parcours réel** : bouton → normalisation existante → `getMerchantPrizes`
   (pages de 40 identifiants) → lectures individuelles des documents `prizes`
   en parallèle dans chaque page → recherche locale du code après toutes les
   pages → résultat/dialogue ou écran de validation. La vérification n'écrit rien.
   `getPrizeWinnerContactForMerchant` n'est appelé que sur l'écran de validation
   pour les coordonnées autorisées du gagnant.

3. **Région Flutter** : `europe-west1` explicite pour `getMerchantPrizes`.
   Les coordonnées utilisent `FirebaseFunctions.instance` (défaut `us-central1`).

4. **Région backend** : `europe-west1` dans `merchant_prizes.js` ;
   `us-central1` via `kFunctionsRegion` pour les coordonnées dans `index.js`.
   Concordance dans le code source ; configuration effectivement déployée non
   interrogée. Aucun déploiement effectué.

5. **Mesures** : instrumentation debug `[MerchantCodeCheck]` avec temps écoulé
   depuis T0 (clic), T1 (départ après peinture du loading), T2 (réponse complète
   ou erreur), T3 (première frame du résultat). Chaque page indique aussi
   `callableMs`, `firestoreMs` et le nombre de documents. Soustraire T1 de T2
   pour la durée totale réseau/recherche, et T2 de T3 pour l'affichage.
   Exemple exécuté en test avec Firebase simulé, code valide : T0=0 ms,
   T1=29 ms, T2=30 ms, T3=102 ms, soit 1 ms de recherche simulée et 72 ms
   jusqu'à la frame du résultat. **Ces valeurs ne mesurent pas la production.**
   Le test lent avance l'horloge virtuelle de 2 secondes ; le timeout de
   15 secondes est testé en avançant de 16 secondes. Le Stopwatch mesure le
   temps mural et ne doit pas être interprété comme l'horloge virtuelle.
   Aucune durée réelle sur téléphone disponible dans cette session.

6. **Coûts identifiés** : recherche exhaustive des lots accessibles au marchand,
   absence de filtre par code côté serveur, relecture des documents déjà lus
   par le backend, pages séquentielles et nouvelle recherche des enseignes à
   chaque page. Ce ne sont pas des scans de toute la collection : le serveur
   utilise des requêtes filtrées et bornées, puis le client parcourt tous les
   résultats du marchand. Les requêtes d'une même phase sont déjà parallèles.
   La cause dominante de la lenteur sur l'appareil reste à confirmer avec les
   mesures ajoutées ; cold start, qualité réseau et localisation Firestore ne
   sont pas mesurés. Aucun `minInstances` n'est configuré pour ce callable,
   ce qui ne prouve pas qu'un cold start a eu lieu. Aucun nouvel endpoint créé.

7. **Nombre de requêtes/lectures** : pour S enseignes possédées et P pages,
   `ownedShops` fait 8 requêtes par page, puis `merchantPrizesPage` en fait
   4+S, chacune limitée à 41 documents. Total : P appels callable et
   P×(12+S) requêtes backend, plus N lectures individuelles côté client pour
   N identifiants retournés. Les lectures de documents dépendent des résultats,
   des recouvrements et de la pagination : au plus 41×(4+S) documents de lots
   renvoyés par les requêtes d'une page, avant dédoublonnage. Ce comptage ne
   comprend pas les lectures des règles ni les minimums de facturation des
   requêtes vides. Le callable de coordonnées effectue ensuite 3 à 4 lectures
   séquentielles (lot, appelant, enseigne éventuelle, gagnant).

8. **UX** : état loading avant réseau, champ et bouton désactivés, spinner et
   « Vérification... », largeur et hauteur du bouton conservées. Messages
   distincts pour code invalide, lot retiré, code expiré et incident technique.
   Le titre de l'écran de validation affiche « Code valide » pour un lot
   disponible ; ses informations et sa confirmation restent présentes.
   Aucune date de retrait n'est produite par le parcours actuel (`claimed`
   uniquement), donc aucune date inventée. Les coordonnées sont chargées une
   fois par écran, avec timeout et affichage du fallback existant en cas
   d'échec ; le Future n'est plus recréé à chaque build.

9. **Double clic et sécurité** : garde synchrone `_isCheckingCode`, bouton
   désactivé et une seule requête pendant l'attente. Deadline globale de
   15 secondes, libération du loading dans `finally`, nouvelle tentative
   possible, réponses tardives ignorées et aucune page supplémentaire après
   expiration. Une requête Firebase déjà partie n'est pas annulable.
   Vérifications `mounted` et route courante avant résultat/navigation.
   Le retrait reste transactionnel, et les règles existantes n'autorisent
   qu'une transition non retiré → retiré. Une répétition est refusée plutôt
   que renvoyée comme succès : effet unique, pas de double remise enregistrée.
   Aucun changement des règles ou de cette logique métier.
   Les nouvelles traces ne contiennent ni code, ni identité, ni coordonnées ;
   les logs Flutter de coordonnées n'affichent plus les erreurs brutes.

10. **Tests exécutés** : 9 nouveaux tests Flutter passent : valide sans écriture,
    invalide, retiré, expiré, réseau, réponse lente, timeout/réessai/réponse
    tardive, dispose, navigation. Le double clic et les dimensions sont vérifiés
    dans les scénarios en attente. Analyse Dart des fichiers concernés : aucun
    problème. Suite complète `merchant_presentation_test.dart` : 42 réussites,
    1 échec préexistant (`merchant screens show errors and retry to empty without
    a loop`, RenderFlex de 26 px à largeur 320 et échelle texte 1,5), reproduit
    avec le fichier Home de HEAD puis restauration du correctif.
    Émulateur Firestore, projet `demo-proxiplay-merchant-prizes` : 5 tests passent,
    dont le nouveau test de retraits concurrents (exactement un succès), les
    autorisations, la pagination et le refus d'un nouvel usage.

11. **`git diff --check`** : réussi, sans erreur de whitespace. Avertissements
    Git de conversion LF/CRLF uniquement.

12. **État Git** : modifications du correctif dans les deux écrans commerçants,
    `merchant_prizes_service.dart`, `prize_winner_contact.dart`, les deux fichiers
    de tests et ce rapport. Les modifications préexistantes de
    `merchant_offered_by_bubble.dart`, `lot_detail_joueur_page_widget.dart`,
    `referral_game_card.dart`, les quatre patchs non suivis et
    `firebase/functions/rapport_repair.json` ont été conservés.

Validation terrain restante : exécuter une vérification en build debug avec
le compte commerçant concerné, relever T0/T1/T2/T3 et les temps de chaque page,
puis comparer premier appel et appels suivants aux logs serveur. La capture
fournie seule ne permet pas d'attribuer une durée ou de prouver un cold start.

Aucun commit, push ou déploiement.

Sortie finale de `git status --short` :

```text
 M firebase/functions/test/merchant_prizes.test.js
 M lib/components/merchant_offered_by_bubble.dart
 M lib/pages/commercant/home_commercant_page/home_commercant_page_widget.dart
 M lib/pages/commercant/validation_lot_commercant_page/validation_lot_commercant_page_widget.dart
 M lib/pages/joueur/lot_detail_joueur_page/lot_detail_joueur_page_widget.dart
 M lib/services/merchant_prizes_service.dart
 M lib/utils/prize_winner_contact.dart
 M lib/widgets/referral_game_card.dart
 M test/merchant_presentation_test.dart
?? 26b2de7-mesgains-csv-jeu.patch
?? 4e8f562-export-winners.patch
?? a51a3b1-export-mediastore-downloads.patch
?? develop-pending-2-commits.patch
?? docs/merchant-winning-code-audit.md
?? firebase/functions/rapport_repair.json
```
