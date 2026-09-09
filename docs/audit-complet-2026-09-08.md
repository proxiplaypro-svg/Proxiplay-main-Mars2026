# Audit critique Proxiplay — 8 septembre 2026

## A. État global

**Note : C — risques importants.** Les principaux moteurs matérialisent leurs gains dans des transactions, mais le produit ne peut pas être déclaré cohérent et robuste de bout en bout. Des failles d'accès, des circuits de qualification divergents et des gains potentiellement invisibles ou difficiles à retirer subsistent.

Périmètre : code local de `develop` à `12bd6aa`, comparaison avec `main` à `48cd073`, soit **43 commits** exclusifs et 53 fichiers modifiés. Les références distantes locales pointent aux mêmes commits ; aucun fetch n'a été effectué. Les 43 commits ont été examinés par historique et changements de fichiers, puis les moteurs antérieurs toujours appelés ont été suivis. Inventaire établi **avant correction** : [audit-flux-2026-09-08.md](audit-flux-2026-09-08.md). Historique détaillé et inventaire des tests : [audit-annexes-2026-09-08.md](audit-annexes-2026-09-08.md).

**Ce rapport ne certifie pas la production.** Aucun déploiement, aucune lecture de la base distante, aucun envoi de notification réelle, aucune migration ni réparation historique. La console `proxiplay-admin` est un autre dépôt, absent de ce workspace : son code de création et son bouton « Terminer » ne peuvent pas être validés ici. Les commentaires qui évoquent cette console ne constituent pas une preuve de son implémentation actuelle. Le fichier local préexistant `firebase/functions/rapport_repair.json` est laissé intact.

### Lecture des résultats

« Corrigé localement » signifie code modifié et contrôlé dans ce workspace. « Transaction vérifiée » désigne des tests locaux des écritures ; cela ne prouve ni l'exécution d'un cron déployé, ni une notification effectivement reçue, ni le rendu sur deux téléphones. Les vérifications d'index sont documentaires : l'émulateur ne remplace pas la vérification des index réellement déployés.

## B. Tableau par fonctionnalité

| Fonctionnalité | État | Code | Firestore | Index | Tests | Risque | Action |
|---|---|---|---|---|---|---|---|
| Jeux classiques | C | callable actif ; contrôles dates/jour | participation et débit transactionnels | instant_winners manquant, ajouté | participation et mineurs | P0/P1 | déployer index ; définir contrôles de statut serveur |
| Gains instantanés | B sous réserve | génération serveur ; créneau le plus récent | créneau, prize et my_lots atomiques | ajouté | sélection, participation, lecture lots | P1 | vérifier génération sur tous les jeux existants |
| Tirage final | C | pickMainPrizeWinners | transaction et garde gagnant ; sélection hors transaction | présent | zéro, un, concurrence, rollback ajoutés | P0 | exclure comptes supprimés ; formaliser états vides et revalidation |
| Lots | C | convention usage_deadline partielle | retrait expiré désormais refusé au commerçant | lecture directe/simple | retrait expiré/utilisé ajouté | P0 | rules + build ; décider retrait des lots plateforme |
| my_lots | B sur gains neufs | ID du prize réutilisé | atomique dans les cinq moteurs | lecture sous utilisateur sans composite | liens, réparations, lecture | P0 historique | auditer orphelins et gagnants non matérialisés |
| Affichage Mes lots | C | stream my_lots puis get prize | filtre par chemin utilisateur | aucun composite | contrats Firestore, pas test appareil | P2 | erreur de lecture désormais affichée ; rafraîchir les états après retrait |
| Parrainage | C | moteur de tirage unique ; acceptance séparée du ticket | ordre lectures/écritures corrigé | status/start et status/end présents | ticket, tirage, exclusion, concurrence | P0 | décider reprise atomique acceptance→ticket ; auditer les tickets manquants |
| Animations | C | cron et réparation exportés ; doublon Flutter encore appelé | attribution atomique ; ancien suivi utilisateur interdit | index 12bd6aa exact | tirage/réparation existants ; runner ajouté | P1 | aligner suivi et affichage gagnant sur données publiques minimales |
| Challenge assiduité | C | cron 01h ; erreurs désormais remontées | qualification + tirage transactionnels | groupe month ajouté | calendrier, qualification, tirage existants | P1 | déployer ; surveiller configurations et rattrapages |
| Resto/commerçant du mois | C | alias restaurant→merchant, moteur mensuel commun | lot sans enseigne_id/owner_id | même groupe month | moteur partagé ; circuit retrait non prouvé | P1/P2 | valider règle des jours et remise du lot |
| Bonus fidélité | B technique | +3 parties chaque 10 participations du jeu | dans transaction | aucun propre | couverture participation partielle | P2 métier | confirmer que le seuil global est voulu |
| Jeux admin | Non certifié | console externe absente | lecteurs commerçants utilisent create_by | index existants games | pas E2E console | P1 | tester contrat owner/create_by/enseigne sur l'autre dépôt |
| QR / accès illimité | C | from_qr client ; allGamesAccessUntil | débit désactivé si accès actif | mêmes index jeux | tests lancement/accès Flutter | P2 | décider si QR doit prouver une présence en magasin |
| Google Places | C | recherche, picker, détails, secret ; pas de cron refresh | onWrite au changement d'ID seulement | document direct | recherche/détails/trigger mockés | P2 | secret/API + reprise erreur + protection événements désordonnés |

## C. Bugs et risques classés

### P0 — sécurité, pertes de gains, incohérences

1. **Élévation de privilèges à l'inscription — corrigée localement.** `firebase/firestore.rules`, `isAdmin()` accepte `userRole == admin`, alors que `isAllowedSelfUserCreate()` ne contrôlait que `user_role`. Un nouveau compte pouvait se créer avec `user_role: joueur, userRole: admin`, puis utiliser les privilèges Firestore admin. Le nouveau test échouait avant correction et passe après ajout de la validation de l'alias. Cela n'assainit aucun compte historique : rechercher les aliases admin inattendus avec un audit dédié des comptes, sans les supprimer automatiquement.

2. **Listes de champs protégés contournables — corrigées localement.** `isSafeMerchantEnseigneUpdate`, `isSafeMerchantGameUpdate` et `isPrizeClaimValidationUpdate` utilisaient `changedKeys()`, qui ne couvre pas les ajouts/suppressions. Un propriétaire pouvait ajouter `hasWinner`, une note Google absente ou `winner_id` pendant `claimed=true`. Remplacement par `affectedKeys()`, testé en émulateur. Les créations initiales d'enseigne/jeu restent peu contraintes : elles ne valident pas exhaustivement la propriété de l'enseigne, les stocks et tous les champs réservés.

3. **`prizes` reste public — non modifié.** `firestore.rules`, bloc `/prizes`, conserve explicitement `allow read: if true` depuis `2052222`. N'importe qui peut lire les codes de retrait, les références de gagnants et les champs dénormalisés. Le retour aux règles strictes est une décision de compatibilité des applications installées, explicitement différée dans le dépôt. Les sept tests de confidentialité désactivés doivent être réactivés lors de ce retour. Attention : `lib/services/global_ticker_service.dart` fait encore une lecture publique des derniers prizes, et les gagnants publics des fiches jeux utilisent aussi cette collection. Refermer la règle exige de valider **tous** ces lecteurs, pas uniquement les requêtes commerçant corrigées.

4. **`merchants` modifiable par tout compte connecté — non modifié.** Le bloc `/merchants/{document=**}` autorise toute écriture authentifiée. Les règles legacy `/jeux` utilisent ensuite l'e-mail d'un document merchant pour décider qui peut gérer un jeu. Un compte peut fabriquer/modifier cette relation. L'accès aux jeux legacy est donc vulnérable. Corriger avec le dépôt admin et migrer vers des identifiants de propriétaires non contrôlés par le client ; cette compatibilité n'est pas prouvable ici.

5. **Perte de ticket entre acceptation et attribution — non modifiée.** `src/share_promo/index.ts:369–429` : transaction de `registerReferralAcceptance`, puis recomputations, recherche du jeu actif, puis `addReferralGameTicket` dans une autre transaction. Une panne ou une fin de période entre les deux peut laisser un filleul accepté sans ticket. Rejouer l'acceptation est ensuite refusé. `adminReconcileReferralGameTickets` existe, mais n'est pas un rattrapage automatique garanti et `addReferralGameTicket` refuse un jeu déjà ended. Il faut définir une attribution persistée dès l'acceptation ou une file de reprise avant tirage ; ne pas ajouter des tickets après désignation du gagnant sans décision métier.

6. **Tirage principal peut désigner un compte supprimé/suspendu — non modifié.** `index.js:5787–5867` ne filtre que la présence de `participant.user_id`. Le profil est lu mais son absence devient `{}` ; un prize et un my_lots peuvent être écrits sous un utilisateur inexistant. Animations, parrainage et mensuel appliquent des exclusions, le principal non. À décider : exclure et retirer au sort, annuler ou conserver les droits du gagnant supprimé. La sélection des tickets et plusieurs données du jeu sont aussi lues hors transaction ; une modification de date/lot entre sélection et commit n'est pas revalidée.

7. **Réparations et états historiques partiels — non modifiés.** `draw_animation_winner.js` et `referral_game_engine.js` conservent un prize déterministe déjà existant sans vérifier que son gagnant correspond au gagnant sélectionné/réparé. Le my_lots créé peut alors pointer vers un prize d'un autre joueur. Le mensuel réécrit son prize déterministe si le journal de tirage final a disparu. Ces cas ne sont pas produits par un commit normal atomique, mais sont possibles avec anciennes données, suppression admin ou réparation. Auditer avant tout rattrapage ; l'ID déterministe ne suffit pas à garantir la cohérence.

8. **Retrait expiré possible — corrigé localement pour le commerçant.** Les règles ne testaient que la transition claimed. Elles vérifient maintenant `request.time <= usage_deadline`, acceptent l'absence/null historique et refusent une date mal typée. L'admin garde son droit général de mise à jour. Flutter utilise `isAvailable` pour le code, le bouton de retrait et les compteurs ; un lot expiré est étiqueté. La barrière de sécurité reste l'heure serveur des rules, y compris pour une ancienne application ou un écran resté ouvert. Aucun ancien prize n'a été modifié.

### P1 — fonctions majeures bloquées ou non garanties

9. **Tirage parrainage avec exclusions — corrigé localement.** `referral_game_engine.js` écrivait `eligibility_status: excluded` pendant la boucle, avant de lire d'autres profils ou le prize. Firestore rejette les lectures après une écriture transactionnelle. Les exclusions sont maintenant écrites après toutes les lectures. Test avec un ticket exclu suivi d'un admissible : échec avant correction, succès après, lot unique visible.

10. **Index requis absents — corrigés dans le fichier, pas en production.** Participation : `instant_winners(hasWinner ASC, date ASC)`. Mensuel : index de groupe `monthly_challenges.month`. Notifications favoris : groupe `favorite_enseignes.enseigne_id`. Fiche admin joueur : groupe `participants.user_id`. L'absence de l'index des instants peut bloquer **même une participation perdante**, car la requête est exécutée systématiquement. L'index mensuel manquant peut empêcher la réconciliation préalable au tirage.

11. **Échecs mensuels masqués — corrigés localement.** Le cron `monthly_challenge.js` capturait indistinctement une date future, une erreur de configuration, un index manquant et un échec d'écriture, sans log. Nouveau runner : skip explicite des dates futures, logs structurés par job/ID/code, poursuite des autres tirages, rejet final si une opération échoue. Animations/parrainage utilisaient déjà un log par jeu mais terminaient en succès malgré ces erreurs : même correction. Les erreurs de requête initiale sont désormais contextualisées et relancées. Les deux imports des cron dans index.js échouent explicitement au lieu de supprimer silencieusement l'export.

12. **Deux suivis d'animation incompatibles — non modifiés.** Le serveur écrit `animations/{id}/entries/{uid}` avec `visited_merchant_ids`, `threshold_reached`. `lib/backend/animation_utils.dart` écrit `users/{uid}/animations/{id}`, champs `visited_merchants`, `qualified`. Il est encore appelé depuis `jeu_detail_joueur_page` et `share_jeu_page` après succès serveur ; ce n'est donc pas du code mort. Les rules n'autorisent pas cette sous-collection : le second suivi échoue, et sa boîte de dialogue « nouvellement qualifié » ne fonctionne pas. Côté serveur, le suivi animation est lui-même dans un catch qui journalise puis poursuit la participation : une erreur peut consommer la partie sans compter l'animation. Définir une unique réponse serveur de qualification et la sémantique de rollback avant suppression de l'implémentation parallèle.

13. **Gagnant d'animation invisible côté joueur — non modifié.** `animation_detail_page_widget.dart:1328` lit `animations/{id}/winner/current`. Les règles publiques du document parent ne s'appliquent pas aux sous-collections et aucune règle winner n'est définie. L'écran masque les erreurs avec un widget vide. Ce document contient aussi e-mail et label pouvant être un nom complet ou un e-mail : ne pas simplement le rendre public. Créer une projection publique minimale prénom/ville, puis migrer le lecteur et traiter les anciens tirages après validation.

14. **Jeux admin non garantis côté commerçant.** `jeux_commercant_page_widget.dart:555` interroge uniquement `create_by == currentUserReference`, limite 15, puis filtre en mémoire sans pagination. Un jeu admin avec `owner_id` correct mais `create_by=admin` sera absent ; des jeux actifs peuvent être hors des 15 premiers documents. Les lots principaux/instantanés prennent aussi `create_by` comme owner en priorité. Il faut tester l'écriture effective du dépôt admin pour un et plusieurs commerçants. La liaison `enseigne_game` n'est pas utilisée comme solution de secours dans cette liste.

### P2 — défauts importants et reprises manquantes

15. **Fin de jeu sans participants non finalisée.** Principal : journalise puis laisse hasWinner=false ; animation sans aucune entrée qualifiée : retourne `no_qualified_entries` et laisse active. Les cron retraitent ces documents chaque nuit. Animation avec entrées toutes exclues, parrainage vide et mensuel vide sont au contraire finalisés. Un test animation actuel impose explicitement le comportement « retente la nuit suivante ». Décision métier nécessaire avant harmonisation ; une absence de gagnant n'est pas automatiquement un tirage raté.

16. **Notifications : garanties limitées.** `notifyPrizeWon` est le point commun onCreate de prizes. Les tests vérifient deux appels successifs pour l'e-mail commerçant ; les pushes génériques ont des IDs déterministes. L'animation conserve en plus `notifyAnimationWinner`, e-mail et push propres : le retrait de la notification doublon dans `571aadd` n'a pas éliminé cette seconde chaîne. Une panne SMTP y empêche aussi le push dans le même try. Après winner_uid, le cron ne rejoue pas la notification ; `repairAnimationDraw` ne la renvoie pas. Une panne entre envoi SMTP et marqueur persistant peut produire un doublon ; aucun exactly-once externe n'est démontré. Les logs existants incluent encore codes/e-mails. Les réparations de lien seules ne déclenchent pas onCreate prize.

17. **Mes lots ne suit pas les mises à jour de prizes en temps réel.** Le stream écoute my_lots ; chaque prize est chargé par `get()`. Si un commerçant met claimed=true pendant que le joueur garde la page ouverte, my_lots ne change pas. Le détail utilise aussi un objet de navigation, pas un stream du lot. Un rechargement/reconstruction relit les données, mais l'actualisation immédiate multi-appareil n'est pas prouvée. Les erreurs get étaient ignorées lot par lot : maintenant la liste montre son erreur existante au lieu de donner une liste partielle trompeuse. Les références vers des documents absents sont toujours omises, à détecter par audit. Le compteur de profil conserve un chargement tolérant aux erreurs et peut être partiel.

18. **Réparation my_lots incomplète et suppression volontaire.** `prize_my_lots_repair.js` vérifie seulement l'existence du lien canonique `my_lots/{prizeId}`, pas la bonne référence dans un lien existant, les IDs historiques aléatoires, les doublons ou l'existence du compte gagnant. La suppression joueur retire uniquement my_lots : le script d'audit le considérera ensuite manquant et la réparation le fera réapparaître. Aucun tombstone ne distingue suppression choisie et perte technique. Ne pas lancer `--apply --confirm` globalement sur la seule foi du compteur.

19. **Lots plateforme sans circuit commerçant complet.** Les payloads animation, referral_game et monthly_challenge n'ont pas d'owner_id/enseigne_id normalisés, même si la configuration mensuelle possède un partenaire. Ils sont lisibles via my_lots, et le détail possède un mode sans jeu, mais la validation commerçant ne peut pas en déduire un droit de retrait. Les dates de validité ne sont pas propagées dans ces trois moteurs. Définir la remise par Proxiplay/admin ou par un partenaire avant de changer ces données.

20. **Participation : barrières client insuffisantes comme sécurité.** Le serveur contrôle les dates, le mineur et le booléen from_qr, mais ne contrôle pas un statut de jeu actif/annulé ni un statut joueur suspendu dans ce callable. Le booléen QR peut être envoyé directement : il ne prouve pas un scan sur place. Le quota de trois parties est réinitialisé par cron à minuit Paris, pas par normalisation atomique au premier jeu du jour ; une panne de reset ou une participation concurrente au batch de reset peut produire un solde inattendu. Le bonus de trois parties concerne la dixième participation **du jeu**, pas la dixième du joueur. Ces politiques doivent être explicitées.

21. **Google Places sans refresh périodique ni reprise fiable.** `google_place_rating_refresh.js` ne se déclenche utilement que quand google_place_id change. Sur indisponibilité Google, il logue puis retourne null ; une édition sans changement d'ID ne retente rien, et une ancienne note peut rester affichée. Deux changements A→B→C avec réponses inversées peuvent écrire la note de B sur C : pas de relecture transactionnelle de l'ID avant update. La recherche est ouverte à tout authentifié, sans quota applicatif/contrôle de rôle. Les fields Google dynamiques sont maintenant protégés contre leur ajout en update commerçant, mais pas exhaustivement à la création initiale. Ajouter une stratégie de fraîcheur, une reprise et une comparaison d'ID est un travail distinct.

22. **Activation parrainage non transactionnelle.** `autoManageReferralGames` lit drafts puis active avant un update séparé. Deux invocations/une activation admin concurrente peuvent activer deux jeux ; `findActiveReferralGame` lève alors une erreur. Un jeu actif déjà échu peut aussi bloquer le suivant jusqu'au cron nocturne. L'activation manuelle externe ne peut pas être vérifiée ici.

23. **Suppressions et sources orphelines.** `deleteEnseigneAndGames`, `deleteCommercantAccount`, `onUserDeleted` et les droits de suppression directe ne forment pas une cascade atomique avec prizes/my_lots et les sous-collections. Les joueurs peuvent conserver un lot dont le jeu ou le commerçant est supprimé. La suppression du seul document user autorisée au client permet aussi sa recréation et peut réinitialiser des champs contrôlés par les triggers. Définir archivage et suppression de compte cohérents avant automatisation.

### P3 — UX et dette

24. Badge tickets : même source `games/{id}/participants.where(user_id==joueur)` que le tirage principal, donc les tickets valides sont comptés, pas les parties disponibles. Mais les erreurs de stream sont affichées comme zéro/absence de badge. La préférence d'animation est indexée uniquement par gameId, pas par utilisateur ; un changement de compte peut fausser l'animation, sans donner les tickets d'un autre compte.

25. Prénom/ville sont dénormalisés sur gains classiques, instantanés et mensuels ; les anciens champs sont compatibles avec plusieurs conventions camel/snake. Le parrainage ne produit pas ces noms publics, et sa fiche joueur actuelle ne rend aucun winner. Les APIs de contact commerçant doivent rester réservées au propriétaire, même quand les fiches publiques évoluent.

26. `index.js` reste monolithique et certains chargements de modules notifications/Places/share_promo gardent un catch « not loaded yet ». Le bundle TS versionné correspond à la compilation locale (pas de différence de contenu après compile). Ce n'est pas un deuxième moteur de parrainage indépendant : les sources TS et JS générées correspondent. `drawWinnerForReferralGame` a bien disparu avec `bc461c2`, et `autoManageReferralGames` ne tire plus depuis `d3d72af`.

## D. Actions externes nécessaires

1. Examiner et déployer **les rules corrigées** : `firebase deploy --only firestore:rules --project <PROJET>`. L'accès public temporaire aux prizes n'est pas refermé par cette commande ; il faut un changement supplémentaire coordonné avec les applications et le ticker public. Vérifier les comptes admin existants avant de considérer l'élévation de privilèges résolue.
2. Déployer les index : `firebase deploy --only firestore:indexes --project <PROJET>`, puis attendre l'état prêt. Vérifier particulièrement instant_winners, monthly_challenges.month et animations/status/end_date. Ne pas supposer que les index déjà présents dans Git sont actifs à distance.
3. Déployer les Functions modifiées, après revue : `firebase deploy --only functions:drawAnimationWinners,functions:drawReferralGameWinner,functions:adminDrawReferralGameWinner,functions:drawMonthlyChallengeWinner --project <PROJET>`. Le helper est empaqueté avec les fonctions qui l'importent. Le changement de chargement des exports s'applique lors de l'analyse du code source au déploiement.
4. Vérifier dans Cloud Scheduler les jobs réellement présents, leur région, leur timezone, leur cible et leur dernier succès. Créer une alerte sur les invocations en erreur et les événements `DRAW_QUERY_FAILED` / `DRAW_FAILED`. Le code n'ajoute pas une politique de retry Scheduler ; le prochain cron repasse sur les éléments encore sélectionnables.
5. Publier un nouveau build mobile pour les messages d'expiration, compteurs et erreurs de chargement. Vérifier physiquement retrait, rechargement, changement de compte et deux appareils. La règle serveur protège aussi les anciennes versions contre un retrait expiré.
6. Google : secret `GOOGLE_PLACES_API_KEY`, liaison au runtime, activation de Places API adaptée aux endpoints v1, facturation, restrictions et quotas. La clé n'est pas embarquée dans le picker Flutter. Vérifier `searchGooglePlaces` et `refreshGooglePlaceRating` réellement déployés. Il n'existe pas de cron de refresh périodique dans ce dépôt.
7. Notifications : vérifier configuration SMTP, autorisations et jetons FCM, trigger onCreate et consumer ff_push_notifications. Les tests locaux stubent SMTP ; ils ne prouvent aucune livraison.
8. Audit distant en lecture seule, revue des résultats, puis seulement sélection explicite des réparations. Le rattrapage d'une animation active échue sans winner est tenté au cron suivant ; une animation déjà ended sans winner n'est pas sélectionnée. `adminRepairAnimationDraw` ne choisit pas un nouveau gagnant s'il n'y a pas winner_uid. Une vraie reprise de tirage doit être conçue/testée avec contrôle d'échéance, candidats et audit trail, sans repasser arbitrairement les documents en active.

### Contrat des requêtes et index

| Requête réelle | Portée | Déclaration au début de l'audit | Résultat |
|---|---|---|---|
| animations status==active, end_date<=now | COLLECTION | status ASC/end_date ASC, 12bd6aa | exacte ; aucun autre composite dans drawAnimationWinners |
| animations/{id}/entries threshold_reached==true | sous-collection | index simple automatique | pas de composite requis |
| games animation_id==id (notifications animation) | COLLECTION | index simple automatique | pas de composite requis |
| games hasWinner==false, end_date<=now | COLLECTION | présent | principal couvert |
| games/{id}/instant_winners hasWinner==false, date<=now, orderBy date ASC | COLLECTION | absent | ajouté |
| referral_games status==draft,start_date<=now et status==active,end_date<=now | COLLECTION | deux composites présents | couverts, déploiement inconnu |
| monthly_challenges month==mois, enabled==true (requêtes séparées) | COLLECTION | simples | couverts par index par champ |
| monthly_challenges group month==mois (réconciliation/stats) | COLLECTION_GROUP | absent | ajouté avec maintien des index de collection |
| monthly_challenge_entries month==mois,status==qualified | COLLECTION | pas de composite dédié | égalités simples fusionnables ; ne pas confondre avec groupe filtré |
| favorite_enseignes group enseigne_id==ref | COLLECTION_GROUP | absent | ajouté |
| participants group user_id==ref (fiche admin joueur) | COLLECTION_GROUP | absent | ajouté ; évite le fallback scan complet |
| my_lots sous utilisateur, puis prizeRef.get | document/sous-collection | aucune dépendance composite | cohérent avec rules propriétaire |
| prizes game_id+owner_id / enseigne_id / owner_id+claim_code | COLLECTION | game_id+owner_id présent ; autres égalités simples | test de sécurité actuel peu probant car lecture publique |
| home games hasWinner + minor optionnel + end_date + ordre prix/date/création | COLLECTION | variantes présentes dans les index games | comparer la variante effective ; index déployés non vérifiés |
| users user_role + player_status_cached in + city optionnelle | COLLECTION | présents | notifications joueurs couvertes |
| ff_push_notifications status + scheduled_time ; created_by + status/ordre | COLLECTION | présents | scheduler et écrans admin couverts |
| referrals inviterUid/createdAt, status/createdAt ; reward_events uid/createdAt | COLLECTION | présents | ordre historique couvert ; égalités rewardStatus fusionnables |
| fcm_tokens group fcm_token==token | COLLECTION_GROUP | présent | couvert |

Les usages de `where/orderBy/collectionGroup` ont été recherchés dans Flutter et les Functions ; les alias de schéma `collectionGroup` ne sont pas à eux seuls des requêtes filtrées exécutées. Les égalités simples peuvent utiliser la fusion d'index ; les requêtes combinant égalité et range, ainsi que les groupes filtrés, nécessitent leurs index adaptés. Référence : [index Firestore](https://firebase.google.com/docs/firestore/query-data/index-overview).

## E. Données potentiellement déjà incohérentes

Aucune quantité de données affectées en production n'est connue. Les scénarios précédents peuvent laisser : gains sans lien joueur ; liens mal dirigés ou dupliqués ; utilisateurs/jeux/enseignes absents ; winner sans prize correspondant ; plusieurs lots finaux ; jeux échus non tirés ; lots échus encore claimed=false. Cette dernière situation peut être normale : l'expiration est calculée, pas un état persisté obligatoire.

Nouveau script strictement en lecture seule :

```powershell
cd firebase/functions
node scripts/audit_game_integrity.js --project=<PROJET> > integrity.json
```

Il parcourt prizes, le groupe my_lots, games, animations, referral_games, monthly_challenge_draws et users par pages. Il compare propriétaires, sources, références, doublons, échéances et gagnants non matérialisés. Il ne sort ni codes de retrait ni e-mails, n'a aucun mode de réparation et échoue explicitement si une lecture échoue. Tests unitaires des anomalies et exécution CLI locale réalisés. Le parcours n'est pas un snapshot transactionnel global ; une activité simultanée peut produire des anomalies temporaires à revérifier. Il conserve les documents en mémoire : prévoir un export/traitement en flux si le volume est très élevé.

Ses alertes `ended_without_winner_needs_review` sont des **candidats à analyser**, pas une autorisation de tirage. Inspecter ensuite entries/participants, critères de qualification, journal de tirage et notifications. Pour un challenge configuré jamais tiré, comparer aussi les configurations monthly_challenges à monthly_challenge_draws : le script ne lit pas ces configurations et ne détecte donc pas à lui seul tous les challenges manquants. Pour les anciennes données avec champs non standards, compléter l'analyse manuelle.

Outils existants : `scripts/audit_my_lots_links.js` sans `--apply`, `scripts/audit_instant_winners.js`, `scripts/audit_home_games_visibility.js`, audits de profil/routage. Ne pas interpréter le rapport de liens absents comme une liste automatiquement réparable : suppression volontaire, ancien ID et gagnant supprimé nécessitent une décision. Les endpoints de réparation animation/parrainage complètent un gagnant déjà désigné, ils ne couvrent pas tous les états ni la reprise des notifications.

## F. Corrections et validation

### Modifications réalisées

- Rules : protection de userRole à l'inscription, affectedKeys sur trois validations, expiration du retrait commerçant.
- Tirage parrainage : toutes les lectures avant les écritures d'exclusion.
- Cron animation/parrainage/mensuel : runner commun avec logs structurés, erreurs de requête contextualisées et échec final visible ; chargement des exports de tirage sans masquage.
- Index : un composite instant_winners et trois champs avec portée COLLECTION_GROUP.
- Flutter : état de disponibilité/expiration du lot, code et validation conditionnés, compteurs excluant les expirés ; erreurs de chargement Mes lots remontées au composant d'erreur existant.
- Audit : inventaire initial, présent rapport, annexe historique/tests et script non destructif d'intégrité.
- Tests : nouvelles régressions de sécurité, index, cron, parrainage, audit et tirage principal ; isolation du projet/fixtures du test de résultat déjà joué.

### Ce qui est testé et ce qui ne l'est pas

| Priorité demandée | Preuve locale | Limite |
|---|---|---|
| gain→my_lots | moteurs animation/mensuel/parrainage + participation et read-path | aucun état distant certifié |
| gagnant unique | tirage principal et parrainage concurrents, répétition des autres moteurs | pas de test charge à grande volumétrie |
| deuxième tirage | garde transactionnelle vérifiée | altération historique du journal reste un risque |
| erreur partielle | erreur injectée après écritures mises en attente du principal ; parrainage invalide | SMTP externe hors transaction |
| zéro participant | tests principal, animation, parrainage, mensuel | comportements finaux différents, explicités plus haut |
| un participant | principal/parrainage/animation | sélection de comptes supprimés du principal non corrigée |
| animation terminée | tests moteur et réparation | pas d'E2E du gagnant Flutter, actuellement bloqué par rules |
| parrainage terminé | tirage et ticket en émulateur | acceptance→ticket pas atomique |
| challenge terminé | tests calendrier/qualification/draw, runner | index groupe prouvé seulement par contrat de fichier |
| expiré/utilisé | nouveaux tests rules, futur et sans date acceptés | admin volontairement conservé comme override |
| rechargement joueur | tests read-path authentifié + persistance prize/my_lots | pas de test UI instrumenté de reload, reconnexion ou autre appareil |

Les tests Places injectent les réponses HTTP ; les tests SMTP remplacent Nodemailer. Les tests existants de confidentialité de prizes sont partiellement désactivés ou démontrent la lecture publique temporaire : leur succès ne valide pas l'absence de fuite. La suite Flutter couvre principalement routage, visibilité, lancement, profil, configuration et majorité ; elle ne parcourt pas le retrait complet.

Résultats chiffrés finaux et commandes reproductibles : voir l'annexe. Les tests ne justifient pas une note B tant que les risques ouverts ci-dessus ne sont pas traités.
