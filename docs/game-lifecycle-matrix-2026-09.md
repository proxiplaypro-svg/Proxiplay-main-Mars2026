# GAME LIFECYCLE MATRIX — PROXIPLAY — septembre 2026

## Derniere mise a jour ? garde de suppression parrainage corrigee ? 10 septembre 2026

**Parrainage : VERT dans le perimetre local demontre. VERDICT GAME ENGINE : B.** Cette mise a jour remplace le dernier ORANGE lie a la suppression et les mentions d'echec conservees dans l'historique ci-dessous. Les autres parcours sont inchanges.

Cause precise : DELETE /api/admin/referral-games/[id] ne controlait pas game.status ; un jeu active sans participant ni gain passait donc la garde et etait supprime avec une reponse 200.

Correction limitee au DELETE : exiger status=draft, conserver les refus existants en presence d'un resultat de tirage, d'une entry ou d'un prize, puis supprimer le seul document du jeu dans la meme transaction que les lectures. Une activation concurrente du document ne peut plus se glisser entre le controle et la suppression. Les controles PATCH, QR/VIP, animations, challenges et retrait sont inchanges.

Suite API admin referral-games-api.test.ts : **7 tests reussis, 0 echec, 0 ignore**, Auth et Firestore locaux reels. Le jeu actif est refuse en 409 et conserve integralement. Les jeux tires, avec participant ou avec gain restent refuses. Statuts ended/null/unknown refuses ; brouillon vide supprime en 200 ; repetition en 404. Le controle d'authentification et les tests d'activation existants restent verts. TypeScript admin : reussi. git diff --check : reussi dans les deux depots.

Fichiers modifies dans ce dernier correctif : admin-proxiplay/app/api/admin/referral-games/[id]/route.ts ; admin-proxiplay/referral-games-api.test.ts ; ce rapport. Pas de modification des moteurs backend : leurs tests de cycle precedemment valides ne sont pas relances inutilement pour cette garde API isolee.

Le verdict demeure B, car cette correction ne realise pas les recettes visuelles/appareils, le renouvellement QR, la revue des historiques ni la validation du packaging Functions mentionnes precedemment. Aucun deploiement, commit, push ou traitement de donnees distantes ; fichiers proteges et travaux locaux preserves.

## Historique des validations precedentes

## Etat courant ? raccordement ADMIN termine localement ? 10 septembre 2026

Cette section remplace les statuts et limites de raccordement admin des sections du 9 septembre, conservees comme historique. Pas d'audit general. Mobile : develop/d35264b, aucun changement QR/VIP dans ce volet. Admin reel : C:/dev/PROXIPLAY/admin-proxiplay, branche wip/commercant-du-mois. 17e2132 toujours non integre. Aucun commit, push, deploiement ou traitement de donnees distantes.

### Resultat par parcours

| Parcours | Preuve du retrait complet | Statut courant |
|---|---|---|
| Animations | Participation reelle, qualification, drawWinnerForAnimation, prize/my_lots, lecture joueur/code, getWinnersList admin reel, action admin via HTTP Firebase, claimed et snapshot atomiques, nouvelle tentative refusee | **VERT dans le perimetre local teste** |
| Parrainage avec lot | Invitation et acceptation reelles, ticket, drawReferralGame, meme parcours admin HTTP et retrait atomique | **ORANGE global**, retrait lui-meme VERT ; ancienne API DELETE autorise encore un cas interdit, voir ci-dessous |
| Challenges mensuels | Participation reelle, qualification mensuelle, tirage, meme parcours admin HTTP ; attendance en integration admin, merchant/restaurant dans les suites backend existantes | **VERT dans le perimetre local teste** |
| Partner | Contrat backend de retrait opere par Proxiplay, lectures gagnant/admin, refus marchand et double validation testes ; meme action admin | Retrait supporte ; pas de producteur partner autonome invente ni de nouvelle recette de remise physique |

### Anciennes voies neutralisees exactement

1. **app/admin/winners/page.tsx ? markPrizesAsRetiredAction ? POST /api/admin/winners/retire** : l'ancien handler dedupliquait prizeIds et effectuait batch.update avec claimed=true, status=claimed et timestamps via Admin SDK, sans verifier le code, l'echeance ni le beneficiaire. Le batch et les imports Admin SDK sont supprimes. Ce POST renvoie desormais **410 Gone** sans aucune ecriture, y compris pour un ancien client. L'action admin appelle exclusivement claimOperatorPrize, dans la bonne region **us-central1** ; les autres Functions restent sur leur region existante europe-west1.
2. **app/admin/campaigns/page.tsx, updatePrizeStatus** : le bouton Valider reclamation ecrivait directement status=reclame et claimed_at, sans meme garantir claimed=true. Cette fonction et les ecritures directes de statut sont supprimees. Le bouton ouvre /admin/winners. L'ancien marquage manuel expire est retire de cette voie ; l'echeance serveur et les statuts historiques d'expiration restent controles.
3. Le retrait en lot sans code n'existe plus dans l'interface : une selection de plusieurs lots ne valide rien. Chaque lot exige le code saisi par l'operateur, jamais automatiquement recopie depuis la valeur affichee. Le beneficiaire est celui de la ligne selectionnee et reste verifie par le serveur. Aucune mutation optimiste claimed : la liste est relue apres la reponse, y compris en cas de perte de reponse.

Les lots merchant restent dans leur circuit commer?ant Flutter existant. L'action admin cible platform/partner et refuse les modes absents/ambigus. Les autorisations generales des administrateurs et leurs acces manuels a la console Firebase ne sont pas refondus : les deux anciennes voies applicatives de retrait identifiees sont bien supprimees, sans modifier les rules.

### Contrat serveur final

Entree : prizeId, winnerId, code et requestId genere pour chaque nouvelle action UI. L'admin doit passer le controle d'acces de l'interface et posseder user_role=admin pour le serveur. Le serveur relit le lot, son gagnant et son lien canonique. Mauvais code, acteur non admin, mauvais gagnant, lien incoherent, echeance passee/invalide ou statut historique expire/expired sont refuses. Les anciens statuts reclame/claimed/retire et timestamps de remise rendent aussi le lot deja utilise, meme si claimed n'avait pas ete correctement renseigne.

La validation ecrit dans **la meme transaction** le prize claimed et le prize_snapshot.claimed du my_lots canonique. Il n'est plus necessaire d'attendre le trigger de synchronisation pour afficher cet etat ; le trigger existant reste compatible. Pas de recreation d'un lien supprime.

**Deuxieme validation : refusee avec already-exists.** Seul le rejeu exact du meme requestId par le meme operateur est reconnu comme une confirmation de la premiere operation, sans nouvelle ecriture ni changement de date. Un nouvel identifiant, un identifiant absent sur un lot utilise ou un autre operateur sont refuses. Les tests distinguent bien ces deux situations.

### Preuve admin et limites honestes

operator-withdrawal.integration.test.ts execute les moteurs de production et les vraies lectures Firestore, puis **la vraie action TypeScript utilisee par le bouton**, le SDK Firebase client, HTTP, le handler onCall de firebase-functions et la verification de jeton par Firebase Admin. Il verifie aussi que le compte est accepte par le garde d'acces admin. Auth et Firestore sont les emuleurs demo locaux. Aucun transport, aucune validation metier et aucune reponse de retrait ne sont mockes. Le snapshot joueur est relu sans appel manuel a syncLotSnapshot.

Le CLI Functions installe echoue au chargement de l'ancien SDK Admin (FieldValue.serverTimestamp indefini dans son mecanisme de substitution). Pour cette raison, test/operator_http_server.cjs heberge le **handler HTTP onCall reel** dans Express local sur 127.0.0.1:5001. La verification des jetons reste active ; un appel sans jeton ou avec un faux jeton est effectivement refuse. Cette preuve n'est pas une validation du packaging complet dans ce CLI. Aucun navigateur/DOM ni clic physique du bouton n'a ete automatise : le raccordement JSX est controle par TypeScript, lint et revue du chemin unique ; la recette visuelle reste a faire. Aucun deploiement n'est revendique.

### Anomalie complementaire conservee visible

La suite admin existante referral-games-api.test.ts donne **4 reussites / 1 echec**. Au test ? suppression admin refuse jeu actif, tire ou draft avec participant ?, ligne 89, la suppression d'un jeu encore actif renvoie **200 au lieu de 409**. Cette route et ce test ne sont pas modifies dans ce chantier. Le defaut empeche d'affirmer que toute l'administration du cycle parrainage est VERT ; il ne contredit pas les preuves du nouveau retrait. Pas de correction de suppression ajoutee silencieusement au perimetre de raccordement des lots. Avant VERT global parrainage, corriger cette garde puis faire passer ce test. Les premieres erreurs de configuration de cette suite ont ete resolues par une initialisation Admin SDK locale sans credentials de production.

### Fichiers modifies dans ce volet

Admin : app/admin/winners/page.tsx ; app/admin/campaigns/page.tsx ; app/api/admin/winners/retire/route.ts ; lib/firebase/adminActions.ts ; lib/firebase/adminQueries.ts ; nouveau lib/firebase/operatorPrizeClaim.ts ; nouveau operator-withdrawal.integration.test.ts.
Mobile/backend : firebase/functions/operator_prize_claim.js ; firebase/functions/test/operator_prize_claim.test.js ; firebase/functions/test/lifecycle_helpers.cjs ; nouveau firebase/functions/test/operator_http_server.cjs ; ce rapport. Aucun fichier Flutter applicatif, QR, rule ou fichier protege modifie dans ce volet. Toutes les modifications GAME LIFECYCLE precedentes sont conservees.

### Verdict courant

**VERDICT GAME ENGINE : B.** Le raccordement du retrait plateforme est effectif localement, avec deux voies directes retirees et une preuve HTTP reelle. Animations et challenges VERT local ; parrainage ORANGE global a cause de son API de suppression.

Ce qui empeche A : garde de suppression parrainage a corriger ; recette visuelle admin et appareils QR a terminer ; incompatibilite du CLI Functions a resoudre avant validation de packaging ; renouvellement QR et revue des historiques ; recette des notifications/projections et remise physique. Aucune de ces conditions n'autorise un deploiement automatique.

## Historique des travaux du 9 septembre

## Mise a jour locale GAME ENGINE C ? B ? 9 septembre 2026

Cette section est l'etat courant et remplace les constats QR/retrait et le verdict de l'audit initial conserve plus bas. Aucun nouvel audit general. Base locale develop/d35264b, modifications GAME LIFECYCLE conservees. Le commit distant 17e21329ed8d461a6929c4d14cb4b9959515f99a est connu mais **non integre** : aucun pull/reset/rebase/merge. Les deux fichiers de rules restent inchanges dans ce chantier.

### Matrice des cycles corriges et limites de preuve

| Moteur | Admission / qualification | Attribution | Prize / my_lots / code | Lecteur joueur | Lecteur legitime | Retrait teste | Retry / cloture | Statut courant |
|---|---|---|---|---|---|---|---|---|
| QR-only / VIP | issueGameQrAccess ? QR opaque ? validateQr dans la transaction de participation ; limites quotidiennes existantes | Instant P et final C reels | Ecritures atomiques existantes, codes conserves | Lectures gagnant sous rules | Proprietaire legitime, autre commercant refuse | Validation marchande reelle sous rules | Meme jour : meme resultat, aucun deuxieme gain ; cloture finale testee | **VERT local**, recette appareils et anciens QR a traiter avant diffusion |
| Animation | Visites reelles, seuil et entry | drawWinnerForAnimation | Prize platform + lien + code + projection publique | Lecture gagnant sous rules | Admin Proxiplay ; pas le commercant visite | **claimOperatorPrize reel**, gagnant/code/lien controles | Deux appels concurrents : claimed puis already_claimed ; un timestamp | **ORANGE** : serveur A ? Z prouve, ancien bouton admin encore a raccorder |
| Parrainage avec lot | Invitation, acceptation, evenement durable, worker, ticket | drawReferralGame | Prize platform + lien + code | Lecture gagnant sous rules | Admin Proxiplay | Meme endpoint reel | Reprise worker, tirage et retrait idempotents | **ORANGE** : integration du bouton admin restante |
| Challenge attendance | Participations reelles sur deux jours Paris, entry qualifiee | Tirage mensuel | Prize platform + lien + code | Lecture gagnant sous rules | Admin Proxiplay | Meme endpoint reel | Tirage et retrait repetes sans second gain | **ORANGE** : integration du bouton admin restante |
| Challenge merchant / restaurant historique | Meme compteur d'assiduite existant, sponsor inchange | Meme moteur mensuel | Prize platform ; le sponsor ne devient pas validateur | Lecture gagnant sous rules | Admin Proxiplay | Meme endpoint reel | Meme preuve pour les deux variantes | **ORANGE** : integration du bouton admin restante |
| Partner | Aucun producteur autonome existant identifie ; pas de nouveau moteur invente | Fixture de contrat seulement | Prize explicitement partner, gagnant, lien, code | Contrat de lecture existant | Admin Proxiplay coordonne la remise | Endpoint reel teste sur fixture partner | Concurrence et retry sans reecriture | **ORANGE** : contrat de retrait prouve, aucun cycle producteur partenaire ni interface dediee demontre |

Classique, instant gagnant, jeux sans lot final et fidelite credits gardent leur contrat existant et font partie de la non-regression. Le rapport ne transforme pas les credits en lots physiques.

### Preuve QR implementee

- Nouveau module backend : firebase/functions/game_qr_access.js. Callable **issueGameQrAccess**, region par defaut us-central1 comme participateInGameTransaction. Auth Firebase obligatoire ; role user_role admin ou commercant proprietaire de l'enseigne, avec verification du owner_id explicite du jeu. Meme source de role que assertIsAdmin existant. Un create_by admin ne prive pas le proprietaire legitime de l'emission.
- Jeton opaque de **256 bits aleatoires cryptographiques**, conserve uniquement dans **game_qr_access/{gameId}**, collection privee sans autorisation cliente. Pas de secret dans le binaire ni dans le document games public. Ce n'est pas une signature HMAC embarquee : le serveur compare le jeton a son enregistrement prive.
- Enregistrement lie au chemin du jeu, de l'enseigne, au owner_id du jeu et au proprietaire canonique de l'enseigne. Ces liens sont relus en transaction. Un changement de rattachement ou de proprietaire invalide le QR precedent.
- Echeance initiale = end_date du jeu. Le jeu conserve en plus ses controles temporels et d'etat. Reemission idempotente ; rotate:true reserve au meme emetteur autorise invalide l'ancien jeton. Aucun appel d'emission/rotation distant execute dans ce chantier.
- Le QR est reutilisable par les clients de la boutique jusqu'a expiration : un QR imprime ne doit pas etre consomme par le premier joueur. L'anti-rejeu metier est la transaction quotidienne existante par jeu/joueur/jour Paris : un retry simultane restitue le meme gain, sans ticket ni debit supplementaire. Le jeton n'est volontairement pas lie a un seul utilisateur.
- Un from_qr=true seul, un token invente, celui d'un autre jeu, expire ou revoque est refuse avant toute attribution. Une possession de QR **ne prouve pas une presence physique** : une photographie ou un lien partage reste utilisable. Aucune geolocalisation/VIP nominatif invente.
- Flutter : GameQrCodeCard demande le jeton pour les jeux qr_only ; les QR publics conservent leur lien simple. Le chargement echoue explicitement et permet de reessayer, sans afficher un faux QR vide. Le jeton qr_token est transporte dans le lien HTTPS, le schema proxiplay et l'intent Android, puis conserve en memoire par jeu pendant la connexion et transmis a la participation. Les scanners du detail jeu et de l'animation le recuperent egalement. Les journaux directs des liens entrants ne contiennent plus leur URI complete.
- Pas de stockage persistant du jeton : apres destruction du processus, rescanner si le lien complet n'est plus disponible. Les anciens QR sans jeton sont refuses pour un jeu QR-only : regeneration/reimpression necessaire, jamais de fallback au booleen. Mobile et page web de lancement doivent etre distribues de facon coordonnee ; une ancienne page qui retire le parametre n'est pas compatible. Aucun deploiement effectue.

### Retrait platform / partner formalise

**Responsabilite inchangee :** commer?ant pour merchant ; Proxiplay pour platform et coordination partner. Les producteurs animation, parrainage et mensuel restent platform, meme lorsqu'un commercant sponsorise le lot. Aucun droit partner autonome n'est cree.

Nouveau callable **claimOperatorPrize**, us-central1, dans firebase/functions/operator_prize_claim.js. Entree : objet {prizeId, winnerId, code}, sous session Firebase d'un utilisateur user_role=admin non exclu. Ces champs sont des identifiants de lot et beneficiaire, pas des donnees de confiance qui autorisent a eux seuls le retrait. L'operateur retrouve le lot dans la liste admin existante ; le gagnant conserve son code dans le detail du lot.

Le endpoint relit dans une transaction : compte operateur, prize, compte gagnant, lien canonique users/{winnerId}/my_lots/{prizeId}. Il refuse role marchand/joueur, mauvais gagnant/code, lien absent/incorrect, gagnant exclu, fulfillment marchand/absent, claimed au type invalide, echeance invalide ou passee. Une absence historique de deadline signifie aucune expiration technique ; claimed absent signifie non reclame uniquement lorsque fulfillment, gagnant, lien et code sont valides. Pas de code genere silencieusement pour un historique ambigu.

Premiere validation : claimed=true, status=claimed, claimed_by_admin=true, claimed_by=reference operateur, claimed_at=horloge serveur, claim_method=operator_v1. Un retry valide d'un retrait operator_v1 renvoie already_claimed sans reecrire le timestamp, meme apres expiration ; les controles d'identite/code restent appliques. Un ancien retrait sans cette methode exige une revue manuelle. Une transaction concurrente ne peut pas effectuer deux validations. La synchronisation my_lots existante est testee apres le retrait.

**Limite a ne pas masquer :** admin-proxiplay/app/api/admin/winners/retire/route.ts et son bouton historique n'ont pas ete modifies ici. Cette ancienne route Admin SDK peut encore ecrire claimed directement sans les controles du nouveau callable ; les administrateurs gardent aussi leurs droits Firestore historiques. Les garanties de transaction/code/echeance sont celles du **nouvel endpoint**, pas de toutes les voies administratives possibles. Avant mise en service, raccorder le bouton a ce contrat et retirer/neutraliser l'ancienne voie pour ces lots. Aucun GO de l'ancienne route ne decoule des tests. Il n'y a pas de nouvelle grande interface admin dans ce chantier.

### Historiques : detection seulement

L'audit existant detectait deja liens absents/incorrects, references orphelines, echeances, proprietaires incoherents et partenaires sans reference. Il pouvait manquer une animation historique prize_type=principal sans fulfillment. Ajout des constats **platform_source_missing_or_wrong_fulfillment** et **operator_prize_missing_code** a inspectIntegrity et test sur fixtures. Rapports sans code ni email ; aucun scan de production, aucun apply, aucune reecriture de proprietaire ou de fulfillment. Un inventaire reel et une decision humaine restent necessaires pour les cas ambigus ; les QR imprimes historiques constituent aussi une migration operationnelle a organiser.

### Fichiers du chantier

Backend nouveau : game_qr_access.js, operator_prize_claim.js. Raccordement : index.js, participate_in_game_transaction.js. Audit : scripts/audit_game_integrity.js et test/game_integrity_audit.test.js. Tests : test/game_lifecycle_qr.test.js, test/operator_prize_claim.test.js, test/lifecycle_helpers.cjs ; les cycles animation/referral/monthly utilisent maintenant le vrai callable de retrait.

Flutter : lib/components/game_qr_code_card_widget.dart ; lib/utils/share_links.dart ; lib/flutter_flow/nav/nav.dart ; lib/pages/public/game_launch_page/game_launch_page_widget.dart ; lib/pages/joueur/jeu_detail_joueur_page/jeu_detail_joueur_page_widget.dart ; lib/pages/joueur/animation_detail_page/animation_detail_page_widget.dart ; test/game_qr_access_test.dart.

Conserves depuis l'audit initial : draw_animation_winner.js, main_prize_draw.js, corrections d'admission/echeance dans participate_in_game_transaction.js, test/draw_animation_winner.test.js, six suites game_lifecycle_*.test.js et leur helper. Les trois fichiers proteges restent hors chantier et hors commit. Aucun fichier admin ni aucune rule modifie.

### Verdict courant

**VERDICT GAME ENGINE : B ? globalement fonctionnel localement avec conditions d'integration explicites.** Le contournement QR par booleen est ferme ; les trois moteurs plateforme disposent d'un retrait serveur reel demontre. Les statuts plateforme restent ORANGE pour l'interface historique non raccordee. Ce verdict n'est pas un GO de deploiement.

Ce qui empeche A :
1. Raccorder le bouton admin au nouvel endpoint et neutraliser sa voie historique pour ces lots.
2. Recetter scan/liens/connexion sur Android et iOS et coordonner le lecteur web/mobile.
3. Regenerer les anciens QR et organiser la rotation en cas de partage non souhaite.
4. Inventorier et arbitrer les lots historiques ambigus, sans migration automatique.
5. Recetter la remise physique, les notifications et les projections asynchrones ; aucun producteur partner autonome prouve.

## Archive ? audit initial avant corrections GAME ENGINE C ? B

Les sections A a J et leurs totaux ci-dessous decrivent l'audit initial. Le ROUGE QR et le verdict C qui y figurent sont historiques ; la section courante ci-dessus et les resultats finaux en fin de fichier font foi.

## Périmètre et méthode

Base auditée : `develop`, `d35264b91089f5d78ff60df45bc33212c86a43f2`. Audit fonctionnel des moteurs, du gain et du retrait uniquement. Aucun audit général de sécurité, changement juridique/SEO/UI, déploiement, backfill appliqué, modification des données distantes, commit ou push. Les trois fichiers locaux protégés sont préservés.

Les fixtures et écritures des tests utilisent exclusivement les émulateurs et des projets `demo-*`. La console admin locale est examinée en lecture seule pour identifier le véritable retrait opérateur. Les tests de cycle exécutent les callables et moteurs réels, puis les lectures et validations Firestore avec les rules strictes. Ils ne simulent pas simplement une série d'écritures attendues. Le déclenchement automatique des notifications/projections par une infrastructure Functions déployée et la remise physique ne sont pas simulés.

**Légende unique :** VERT = cycle complet démontré dans ce périmètre local ; ORANGE = fonctionne mais trou, risque ou compatibilité non prouvé ; ROUGE = cycle cassé ou attribution/retrait potentiellement non fiable. VERT ne constitue pas une autorisation de déploiement ni une recette Android/iOS sur appareils.

## A. Moteurs et variantes réellement présents

1. **Jeu classique `games`, avec lot final** : participation quotidienne puis `drawMainPrize`.
2. **Jeu classique sans lot final**, `hasMainPrize=false` : même participation ; éventuels instants et crédits ; aucune récompense finale à inventer.
3. **Instant gagnant**, sur `games/{id}/instant_winners` : mécanisme supplémentaire du jeu classique, compatible avec ou sans lot final. Un horaire échu ouvre une occurrence ; le prochain participant valide reçoit une occurrence sélectionnée parmi celles échues.
4. **QR-only** : `access_mode=qr_only`, mode d'entrée du même moteur. **VIP** est le badge du `GameAccessType.loyalty` avec QR-only ; `campaign` est le badge « En commerce ». Aucun tirage VIP ou fidélité spécifique n'a été trouvé derrière ces enums.
5. **Animation multi-enseignes** : progression par enseignes distinctes, `animations/{id}/entries/{uid}`, puis `drawWinnerForAnimation`.
6. **Jeu de parrainage** : invitation acceptée, événement durable, ticket par acceptation, tirage pondéré par tickets dans `referral_games`.
7. **Parrainage classique sans jeu actif** : récompense d'accès jusqu'à minuit Paris ou crédits de jeu. Aucun `prize` matériel attendu.
8. **Défi mensuel `attendance`** : assiduité par jours Paris puis tirage mensuel.
9. **Défi mensuel `merchant`** : même assiduité et même moteur ; lot sponsorisé « commerçant du mois ». Le type historique `restaurant` est normalisé vers `merchant`, avec lecture des champs `restaurant_*` et identifiants historiques. Le libellé **« Bonus fidélité »** utilise ce circuit mensuel ; il n'est pas un moteur supplémentaire.
10. **Bonus de trois parties chaque dixième participation du jeu** : position calculée à partir du compteur global `games.participations`, tous joueurs confondus, et non du dixième passage individuel d'un client. Aucun tirage ni lot matériel.

`GameType.scratcher` correspond à la révélation visuelle d'un résultat serveur. `GameType.quiz` existe seulement comme enum dans `lib/backend/schema/enums/enums.dart` : aucun parcours de réponses/score/sélection quiz n'a été trouvé. Il n'est donc pas ajouté artificiellement à la matrice des moteurs exécutables. Les automatismes anniversaire/inactivité examinés dans `lib/notifications/runners` envoient des notifications ; ils ne constituent pas un autre moteur d'attribution de prize.

### Références précises utilisées dans les cellules

| Repère | Fichier et fonction |
|---|---|
| P | [participate_in_game_transaction.js](../firebase/functions/participate_in_game_transaction.js), `participateInGameTransaction`, `getParisDayKey`, `resolveCachedLastResult`, `generateClaimCode` |
| G | [index.js](../firebase/functions/index.js), `generateInstantWinnersForGameCallable` ; [instant_winners_core.js](../firebase/functions/lib/instant_winners_core.js), `buildInstantWinnerPayloads`, `planInstantWinnerReconciliation`, `pickDueInstantWinner` |
| C | [main_prize_draw.js](../firebase/functions/main_prize_draw.js), `drawMainPrize`, `pickMainPrizeWinners` |
| A | [draw_animation_winner.js](../firebase/functions/draw_animation_winner.js), `drawWinnerForAnimation`, `buildPrizePayload`, `notifyAnimationWinner`, `drawAnimationWinners` |
| R | [src/share_promo/index.ts](../firebase/functions/src/share_promo/index.ts), `createReferral`, `registerReferralAcceptance`, `grantReferralRewardInternal` ; runtime compilé sous `lib/share_promo` |
| Q | [referral_reward_queue.js](../firebase/functions/referral_reward_queue.js), `prepareReferralReward`, `processReferralReward`, `retryPendingReferralRewards` |
| D | [referral_game_engine.js](../firebase/functions/referral_game_engine.js), `drawReferralGame`, `prizePayload` ; [draw_referral_game_winner.js](../firebase/functions/draw_referral_game_winner.js), `drawReferralGameWinner` |
| M | [monthly_challenge.js](../firebase/functions/monthly_challenge.js), `prefetchActiveMonthlyChallenges`, `trackMonthlyChallengesParticipation`, `trackMonthlyChallengeParticipation`, `reconcileMonthlyChallengeEligibility`, `drawWinnerForMonthlyChallenge`, `drawMonthlyChallengeWinnerScheduled` |
| B | [src/share_promo/firestore.ts](../firebase/functions/src/share_promo/firestore.ts), `applyRewardToUser`, `getNextMidnightTimestamp`, `isRewardPlayable` ; P pour les crédits de position |
| J | [lots_joueur_page_widget.dart](../lib/pages/joueur/lots_joueur_page/lots_joueur_page_widget.dart), `_loadLotItems` ; [lot_detail_joueur_page_widget.dart](../lib/pages/joueur/lot_detail_joueur_page/lot_detail_joueur_page_widget.dart), branche sans `game_id`, `_buildGamelessLotContent` |
| V | [merchant_prizes.js](../firebase/functions/merchant_prizes.js), `merchantPrizesPage` ; [merchant_prizes_service.dart](../lib/services/merchant_prizes_service.dart), `loadMerchantPrizes`, `canClaimMerchantPrize`, `claimMerchantPrize` ; pages accueil, détail jeu et validation commerçant |
| F | [firestore.rules](../firebase/firestore.rules), `ownsMerchantPrize`, `isMerchantPrize`, `isPrizeClaimValidationUpdate`, bloc `prizes`, bloc `users/{uid}/my_lots` |
| S | [prize_lot_snapshot.js](../firebase/functions/prize_lot_snapshot.js), `syncLotSnapshot` ; [public_winners.js](../firebase/functions/public_winners.js), `publicPrize`, `syncPublicPrizeWinner` |
| N | [index.js](../firebase/functions/index.js), `notifyPrizeWon` ; statut idempotent par canal, demandes de push et SMTP |
| O | Console `C:/dev/PROXIPLAY/admin-proxiplay` : `lib/firebase/adminQueries.ts:getWinnersList`, `app/admin/winners/page.tsx`, `app/api/admin/winners/retire/route.ts:POST` ; `lib/firebase/adminAuth.ts:assertIsAdminRequest` |

## B. Matrice A → Z

Chaque repère renvoie au fichier et à la fonction ci-dessus. « — » signifie non applicable au mécanisme, et non étape manquante. Les résultats des nouveaux tests sont distingués du statut métier : un test de caractérisation QR qui réussit démontre le défaut.

| Type de jeu / mécanisme | Entrée joueur | Éligibilité | Limite participation | Écriture participation | Qualification / ticket | Instant éventuel | Tirage final éventuel | Sélection gagnant | Création prize | Création my_lots | Code | usage_deadline | fulfillment_type | Visibilité joueur | Visibilité commerçant / opérateur | Validation / claim | Notification | Clôture | Retry / idempotence | Test existant | Test de cycle ajouté | Statut final |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Classique avec final | Page jeu → P | Auth, compte non exclu, dates, majorité si requise, propriétaire cohérent : P | 1 / jeu / jour Paris, crédits sauf accès illimité : P | `participants/YYYYMMDD_uid`, détail, unique_players : P | 1 ticket par journée de participation : C | P + G si occurrences | C après échéance | `crypto.randomInt` parmi tickets de comptes valides : C | Principal, transaction C | Même transaction C | Hex 20 caractères : C | Copie `game.prize_usage_deadline` ; contrôle avant attribution : C | merchant : C | J + F ; publicPrize atomique C | V + F | V transaction ; F propriétaire, échéance, false→true | N, asynchrone | hasWinner=true, status=ended ; zéro éligible finalisé : C | Ticket déterministe ; transaction, gardes C | main_prize_draw_audit, rollout_merchant_access | game_lifecycle_classic | VERT |
| Classique sans final | Même P | Même P | Même P | Même P | Tickets conservés, sans tirage final | P + G possibles | Aucun : C | — hors instants | Aucun final | Aucun lien final | — hors instants | — hors instants | — hors instants | Jeu / résultat P ; J si instant | V si instant | V si instant | N si instant | ended + no_main_prize : C, corrigé | Retry C sans nouvel état | audit_security_regressions | game_lifecycle_classic | VERT |
| Instant gagnant | Participation P, après planification G | Même P + occurrence échue non attribuée ; échéance du lot valide | 1 résultat par participation quotidienne P | Ticket + slot.player_id/hasWinner : P | L'occurrence est le gain, pas un ticket final supplémentaire | Oui | Indépendant, C si lot final | G choisit uniformément une occurrence échue | Secondaire auto-ID, transaction P | Même transaction P | Horodatage base36 + 2 octets crypto : P | Copie du jeu ; refus avant gain si invalide/échue : P | merchant | J ; résultat récupérable par P | V + F | V + F, même retrait classique | N | Slot attribué ; jeu reste disponible jusqu'à sa fin | Cache last_result + transaction ; planification G idempotente | instant_winners_core, participate_already_played_no_parts | game_lifecycle_instant | VERT |
| QR-only / VIP / campagne | QR mobile → P avec from_qr=true | P ne prouve que le booléen, aucun secret QR lié au jeu | Même quota quotidien P | Même P | Même C, aucune qualification VIP distincte | Possible P | Possible C | Même P/C | Même P/C | Même P/C | Même P/C | Même P/C | merchant | J | V | V + F | N | Même C/slot | Gain idempotent ; admission QR contournable | participate_minor_restricted_games couvre une autre condition, pas preuve QR | game_lifecycle_qr | ROUGE |
| Animation multi-enseignes | P sur jeux liés par animation_id | Animation active/dates, compte P ; comptes exclus filtrés A | Visite distincte d'enseigne ; quota source P | P + `animations/id/entries/uid` | threshold_reached, visited_merchant_ids : P | Instants propres aux jeux sources possibles | A après fin via cron | Uniforme parmi UID qualifiés valides : A | `animation_id`, type principal, ID animation_id : A | Atomique A | 8 caractères via Math.random : A | Non écrit | platform | J ; public_winner/current atomique A | Opérateur O ; commerçant ne lit pas le prize privé | O ; F autorise admin et refuse commerçant | A après commit + N | ended + winner ; sans qualifié ended/no_eligible_entries corrigé | ID déterministe, transaction, garde A | draw_animation_winner, firestore_rules_animations | game_lifecycle_animation | ORANGE |
| Jeu de parrainage | R invitation puis acceptation filleul | Pas auto-parrainage, compte filleul, invitation non consommée ; parrain éligible Q/D | 1 acceptation par filleul ; plusieurs filleuls = plusieurs tickets | referrals accepted + événement durable : R/Q | entries/referralId, compteur ticket_count : Q | Aucun | D après fin, bloqué si pending non résolu | Pondération par ticket valide : D | ID referral_game_id, transaction D | Atomique D | Hex 10 caractères : D | Non écrit | platform | J | O ; pas de propriétaire boutique implicite | O, pas validation commerçant | N ; pas de notification propre au tirage D | ended + completed ou no_eligible_entries | Outbox, worker idempotent, pas de ticket rétroactif après tirage | referral_acceptance_outage, referral_reward_queue, referral_game_integration | game_lifecycle_referral | ORANGE |
| Parrainage classique, accès illimité | R sans jeu de parrainage actif | Campagne active à la création, quotas R/B | Quotas campagne + 1 acceptation/filleul | referrals + reward_events + share_state : R/B | Droit allGamesAccessUntil, pas ticket de tirage | Gain futur via P seulement | Aucun pour le bonus | — | Aucun attendu | Aucun attendu | Aucun requis | Expiration du droit à minuit Paris : B | — | getSharePromoState + crédit effectif P | — | Utilisation automatique par P | Push bonus via R | rewardStatus=granted ; droit expirant | reward_events/id, transaction R ; worker Q | referral_reward_queue + share_promo | game_lifecycle_referral | VERT |
| Parrainage classique, crédits | R ; rewardType play_credit/plays/remaining_part/game_bonus | Quotas R/B | Même R | reward_events + incrément remaining_part : B | Crédits consommables par P | Gain futur via P seulement | Aucun propre | — | Aucun attendu | Aucun attendu | Aucun requis | Pas d'expiration propre écrite pour ces crédits | — | remaining_part / P | — | Débit par P, aucun retrait matériel | Selon configuration R | rewardStatus=granted | Même transaction R/B | referral_reward_queue | game_lifecycle_referral | VERT |
| Assiduité mensuelle attendance | P sur un jeu valide | Config M active, période/mois, compte valide au tirage | 1 jour compté par utilisateur, tous jeux confondus : M | users/uid/monthly_challenges/id | active_dates/count ; monthly_challenge_entries/id_uid : M | Ceux du jeu source seulement | M à draw_date | Uniforme entre utilisateurs qualifiés valides | monthly_challenge_id : M | Atomique M | Horodatage + 2 octets crypto : M | Non écrit | platform | J + état mensuel | O | O, refus boutique | Push M après commit + N | monthly_challenge_draws.status final ; config conservée | Entry unique, transaction M, statut final | monthly_challenge, participate_with_monthly_challenge | game_lifecycle_monthly | ORANGE |
| Commerçant/resto du mois ; Bonus fidélité | Même P/M | Même M ; sponsor enseigne config, pas preuve de visite chez ce sponsor | Même M | Même M, challenge_id distinct | Même compteur de jours M | Jeu source seulement | Même M | Même M | Type monthly_challenge ; sponsor non recopié en owner_id/enseigne_id | Atomique M | Même M | Non écrit | platform, y compris type merchant | J | O ; pas V pour le sponsor | O ; ce n'est pas un lot marchand classique | Push M + N | Draw distinct, type restaurant normalisé | Config legacy supportée ; tirages indépendants | monthly_challenge | game_lifecycle_monthly (merchant et restaurant) | ORANGE |
| Bonus position 10 | P, compteur global du jeu à 9 avant participation | Participation valide P | Position multiple de 10 ; retry exclu | remaining_part +3 dans transaction P | Crédits, pas ticket additionnel | Indépendant de ce bonus | Aucun propre | Participant à cette position | Aucun attendu | Aucun attendu | Aucun requis | Pas d'expiration propre | — | Résultat messageBonus + compteur joueur P | — | Crédit directement consommable | Réponse P | Transaction de participation | Cache + ticket quotidien P | participate_already_played_no_parts | game_lifecycle_classic | VERT |

## C. Cycles détaillés et preuves

### Classique, sans lot final, instants et QR

`game_lifecycle_classic.test.js` fait participer un joueur à un jeu créé par l'admin et rattaché au commerçant, rejoue la même journée, change de jour Paris, déclenche deux tirages concurrents, retrouve un unique prize et son lien joueur, contrôle les lectures gagnant/commerçant, refuse mauvais gagnant/commerçant et retrait joueur, valide le retrait légitime puis refuse le second. Le snapshot `my_lots` est synchronisé explicitement par le handler réel S. La projection publique classique est écrite par C dans sa transaction ; les assertions de projections/confidentialité complémentaires sont dans `public_winners*.test.js`.

Zéro participant, tous candidats supprimés/suspendus et tirage déjà finalisé ne créent pas de gain fantôme. Sans lot final, la clôture est maintenant enregistrée sans inventer de gagnant. Le changement de journée est testé de `2026-09-09T21:59:59Z` à `22:00:00Z`, soit minuit Paris en septembre. Les tests mensuels existants complètent les utilitaires de calendrier ; cela ne prétend pas tester chaque transition DST sur appareil.

`game_lifecycle_instant.test.js` exécute aussi G : création d'un planning à deux occurrences, répétition sans duplication, progression de l'horloge après échéance des occurrences, deux participations et deux gains distincts, retrait. **La sélection réelle est aléatoire parmi toutes les occurrences échues**. Les autres occurrences restent disponibles. Le vieux commentaire « plus récente puis expiration des autres » était faux ; il a été corrigé sans changer cette règle métier déjà testée par `instant_winners_core.test.js`.

Une réponse perdue après commit ne perd pas le prize : la participation rejouée retrouve `last_result.prize_id`, le lien `my_lots` est déjà durable. L'arrêt avant commit ne laisse ni prize, ni lien, ni slot consommé ; la reprise réalise ensuite le gain et le retrait. La fermeture du processus mobile est représentée par l'abandon de la réponse suivie d'une nouvelle requête ; aucun appareil n'a été forcé à quitter.

La reprise de participation reste soumise à la fenêtre du jeu : après sa fin, P refuse l'appel avant de restituer le cache. Le gain déjà attribué reste accessible par `my_lots` ; il n'est pas nécessaire de pouvoir rejouer le jeu pour lire le lot.

Le slot gagné ne clôture pas le lot final. Plusieurs tickets journaliers du même joueur augmentent ses chances au tirage principal ; le compteur `unique_players` ne sert pas de liste équiprobable au tirage C. Les instants restés non attribués à la fin du jeu ne deviennent pas des gains dus à un joueur : aucune participation après échéance n'est acceptée.

**QR/VIP :** `game_lifecycle_qr.test.js` démontre simultanément que `from_qr=false` est refusé et que `from_qr=true` seul suffit, sans QR signé, nonce, attestation de présence ou liaison cryptographique au `gameId`/enseigne. Les références serveur du jeu et du propriétaire sont vérifiées, mais elles ne prouvent pas le scan. Un même booléen peut être envoyé pour un autre jeu QR. Le test poursuit malgré cela jusqu'au gain instantané, au final et au retrait, afin de distinguer l'admission défectueuse de la fiabilité de l'attribution. Pas de correctif arbitraire de ce protocole dans cet audit.

### Animation

Deux jeux d'enseignes différentes appartenant au **même propriétaire** produisent deux visites : le compteur porte sur les IDs d'enseignes, malgré le nom `visited_merchant_ids`. Rejouer le premier jeu ne qualifie pas deux fois. Le second atteint le seuil, puis deux tirages concurrents produisent un seul prize, un `my_lots`, `winner/current`, `public_winner/current` et l'état final. Le gagnant lit son lot, le commerçant est refusé sur ce lot plateforme, l'opérateur peut le lire et enregistrer le retrait.

Les écritures de la décision et des projections propres à l'animation sont atomiques. L'envoi de notification est après commit, avec erreurs journalisées ; une erreur n'annule pas le prize. Le cron se limite aux animations actives arrivées à échéance. L'helper de tirage est interne ; son éligibilité temporelle dépend du filtre de son appelant, contrairement au contrôle d'échéance interne de C/D/M. La branche sans qualifié est désormais terminale ; les anciens tests qui exigeaient une nouvelle tentative chaque nuit ont été actualisés à ce contrat de clôture.

### Parrainage

Le test utilise les vraies callables de création d'invitation et d'acceptation. L'auto-parrainage est refusé. Une panne injectée après acceptation laisse `referral_reward_pending` durable ; le rejeu de l'acceptation ne crée pas un second événement. Un tirage avec événement pending est bloqué en revue. Deux workers concurrents produisent un ticket et un seul incrément. Le tirage choisit ce parrain, écrit prize/my_lots et clôture ; le chemin de lecture et de retrait opérateur est ensuite testé.

Les tests existants Q complètent : ticket déjà existant, ticket contradictoire, jeu finalisé avant traitement et transaction d'acceptation interrompue. Un événement bloqué ou un prize contradictoire exige une reprise explicite ; il n'est pas transformé silencieusement en un ticket rétroactif ou un nouveau gagnant. Le worker classique traite les événements sans jeu via `grantReferralRewardInternal`.

Les récompenses d'accès et de crédits ne sont pas des lots perdus faute de `prize` : `game_lifecycle_referral.test.js` vérifie le droit jusqu'à minuit, sa consommation sans débit, puis le retour au débit après expiration. Le variant `play_credit` crédite une seule fois et ses crédits sont ensuite consommés par P. Les alias `plays`, `remaining_part`, `game_bonus` suivent le même dispatch B ; un `rewardType` externe non pris en charge ne bénéficie pas de cette preuve.

### Mensuel, restaurant/commerçant et fidélité

Le test part d'une **participation réelle**, pas d'une entry qualifiée préremplie. Deux jours Paris conduisent au seuil, une entry est créée, l'horloge passe à la date de tirage, puis M attribue prize/my_lots et enregistre le résultat. Attendance, merchant et l'ancien type restaurant sont chacun exécutés jusqu'au retrait opérateur. Le test vérifie également l'indépendance des deux défis et la clôture sans qualifié.

La qualification `merchant` n'est pas filtrée par `game.enseigne_id` : `trackMonthlyChallengesParticipation` applique les configs actives aux participations de tous les jeux. Le sponsor n'est pas un lieu de visite obligatoire dans ce code. Il faut une décision produit si « fidélité » doit signifier fidélité à un seul commerce ; aucun nouveau filtre n'a été inventé.

Les trois variantes produisent **`fulfillment_type=platform`**, sans `owner_id`/`enseigne_id` sur le prize, même si la config porte un restaurant. Le code de retrait existe, mais la boutique ne peut pas le valider. Le retrait passe par O ; le joueur voit « Remise du lot organisée par Proxiplay ». La config mensuelle reste conservée et la clôture est celle de `monthly_challenge_draws`, pas un `games.hasWinner` inexistant.

## D. Tests existants mobilisés

Tous les chemins cités ici sont sous `firebase/functions/test/` sauf mention contraire.

| Domaine | Tests existants utiles |
|---|---|
| Participation / retry / données historiques | `participate_already_played_no_parts.test.js`, `participate_minor_restricted_games.test.js`, `audit_security_regressions.test.js` |
| Tirage classique / rollback | `main_prize_draw_audit.test.js`, `scheduled_draw_runner.test.js`, `draw_indexes_contract.test.js` |
| Planning et sélection d'instants | `instant_winners_core.test.js` |
| Animation | `draw_animation_winner.test.js`, `firestore_rules_animations.test.js` |
| Parrainage et reprise durable | `referral_acceptance_outage.test.js`, `referral_reward_queue.test.js`, `referral_game_integration.test.js`, `referral_games_core.test.js` |
| Défis mensuels | `monthly_challenge.test.js`, `participate_with_monthly_challenge.test.js` |
| Visibilité et retrait | `lots_joueur_read_path.test.js`, `rollout_merchant_access.test.js`, `merchant_prizes.test.js`, `get_prize_winner_contact_for_merchant.test.js`, `firestore_rules_prizes_and_my_lots.test.js` |
| Cohérence / projections | `prize_lot_snapshot.test.js`, `prize_my_lots_repair.test.js`, `public_winners.test.js`, `public_winners_security.test.js` |
| Notification idempotente | `notify_prize_won_idempotence.test.js` avec Nodemailer substitué |
| Flutter | Suite existante, dont `test/rollout_prize_compatibility_test.dart` : modèle historique, bénéficiaire, propriétaire, expiration, plateforme |

## E. Tests de cycle ajoutés et corrections locales

- `game_lifecycle_classic.test.js` : cycle final, jour Paris, bonus position, absence de final, zéro candidat, suppression/suspension avant tirage, délai de retrait incohérent.
- `game_lifecycle_instant.test.js` : planning serveur, consommation et retrait, réponse perdue/concurrence, rollback et reprise, occurrences restantes, compte/jeu invalide, expiration après gain et échéance invalide avant attribution.
- `game_lifecycle_animation.test.js` : deux enseignes du même propriétaire, qualification, tirage concurrent, projection publique, retrait opérateur, clôture sans qualifié.
- `game_lifecycle_referral.test.js` : invitation réelle, acceptation durable malgré panne, workers concurrents, tirage et retrait ; accès jusqu'à minuit et crédits consommés dans le moteur.
- `game_lifecycle_monthly.test.js` : attendance, merchant et restaurant historique depuis les participations jusqu'au retrait opérateur ; indépendance des défis.
- `game_lifecycle_qr.test.js` : gain/retrait complets et **caractérisation du contournement QR**.
- `lifecycle_helpers.cjs` : fixtures exclusivement locales, horloge de test, lecture sous authentifications distinctes, retrait et synchronisation réelle S. Ce helper ne remplace aucun moteur d'attribution.

| Défaut observé | Correction locale | Preuve |
|---|---|---|
| Compte suspendu/supprimé marqué, ou jeu annulé/inactif, encore admis par P et susceptible de gagner un instant | P réutilise l'exclusion des tirages avant toute écriture, et refuse les états draft/cancelled/canceled/disabled/ended | Les tests des quatre états échouaient avant correction, passent après ; aucun crédit consommé ni prize créé |
| Jeu sans lot final restant ouvert après sa fin | C clôture `status=ended`, `draw_status=no_main_prize` sans gagnant ; garde de retry | Test de cycle sans lot final, échec reproduit avant correction |
| Animation sans qualifié restant active indéfiniment | A clôture `ended/no_eligible_entries`, puis ignore les retries | Cycle sans qualifié ; test existant de retry nocturne modifié explicitement |
| `prize_usage_deadline` déjà passée pouvant être copiée dans un nouveau gain immédiatement non retirable | P refuse avant attribution/débit ; C retourne `manual_review_required:invalid_or_expired_prize_deadline` sans désigner un gagnant | Tests d'échéance passée ; expiration légitime après attribution reste refusée au commerçant |
| Commentaire P décrivant une autre politique de sélection d'instants | Commentaire aligné sur la sélection aléatoire réelle G et la conservation des autres occurrences | Test de deux occurrences puis deux participants ; politique de sélection inchangée |

Fichiers applicatifs modifiés : `firebase/functions/participate_in_game_transaction.js`, `firebase/functions/main_prize_draw.js`, `firebase/functions/draw_animation_winner.js`. Test existant modifié : `firebase/functions/test/draw_animation_winner.test.js`. Aucun changement mobile, admin, rules ou index dans ce chantier.

## F. Trous fonctionnels encore ouverts

1. **ROUGE — admission QR/VIP déclarative.** Une partie et un gain peuvent être obtenus sans preuve de scan. Il faut un protocole vérifiable lié au jeu et à l'enseigne, avec politique de durée/rejeu, avant de déclarer ce mode complet. Un simple contrôle du badge, du `gameId` ou d'un autre booléen ne résout pas le défaut.
2. **ORANGE — dernier kilomètre plateforme.** O existe réellement : liste générique des prizes, bouton de retrait, POST authentifié admin. Nos tests prouvent les données et permissions de stockage, pas une session navigateur admin, l'authentification HTTP de cette route ni la remise physique. Les lots sponsorisés merchant/restaurant ne rejoignent pas le retrait boutique.
3. **ORANGE — règles de retrait opérateur.** La route O fait un batch `claimed=true`, `status=claimed`, timestamps, sans lecture préalable de l'échéance/état. Un retry remet à jour les timestamps ; aucun contrôle du code n'y est effectué. L'admin possède un droit de dérogation technique, pas le même protocole atomique que le commerçant. Définir les garanties métier attendues avant de durcir cette voie.
4. **ORANGE — unicité des codes non réservée.** Les générateurs n'enregistrent pas de réservation unique ni de contrôle de collision. La recherche mobile normalise le code et sélectionne le premier lot trouvé. Une collision dans le portefeuille d'un commerçant serait ambiguë. Les tests prouvent présence et distinction dans leurs fixtures ; ils ne démontrent pas l'unicité globale de toutes les émissions.
5. **ORANGE — notifications et snapshots asynchrones.** Les effets après commit peuvent manquer malgré un gain durable. Les projections génériques S/N ne sont pas déclenchées automatiquement par les tests qui ne démarrent pas d'émulateur Functions. La notification spécifique animation/mensuelle et la générique peuvent se cumuler. Les textes génériques N évoquent une boutique même pour certains prizes sans boutique ; la page joueur plateforme donne l'indication opérateur. Pas de garantie de réception email/push ni de reprise automatique de chaque effet ici.
6. **ORANGE — intitulés fidélité.** VIP/loyalty n'est pas une éligibilité de fidélité serveur. Le défi sponsorisé compte les jours de participation tous jeux. Toute attente métier différente doit être décidée explicitement, pas déduite du nom du badge.

## G. Contrat prize / my_lots et anomalies de schéma

### Convergence et exceptions

| Producteur | source_type / source_id | winner / user | game_id | owner_id / enseigne_id | fulfillment | usage_deadline | claimed / retrait | my_lots |
|---|---|---|---|---|---|---|---|---|
| Final C | Pas de paire commune ; game_id + prize_type | winner_id référence | Référence games | Références | merchant | Optionnelle, copiée du jeu | false + claim_code | Lien prize_id atomique |
| Instant P | Pas de paire commune ; slot porte player_id, prize ne stocke pas l'ID du slot | winner_id référence | Référence games | Références | merchant | Optionnelle, copiée du jeu | false + claim_code | Lien atomique |
| Animation A | animation_id chaîne ; ID prize déterministe | winner_id référence | Absent | Absents | platform | Absente | false + claim_code | Lien atomique |
| Parrainage D | referral_game_id chaîne ; ID prize déterministe | winner_id référence | Absent | Absents | platform | Absente | false + claim_code | Lien atomique |
| Mensuel M | monthly_challenge_id/type/month + monthly_challenge_draw_ref | winner_id référence | Absent | Absents, même avec sponsor | platform | Absente | false + claim_code | Lien atomique |
| Accès / crédits R/B/P | referralId/reward_events ou compteur de participation | utilisateur crédité | Aucun prize | — | — | Échéance du droit pour accès uniquement | Consommation automatique | Aucun attendu |

Le nom `prize_type=principal` est partagé par final classique et animation : **ne pas déduire le validateur du seul type**. `fulfillment_type` permet de les distinguer. Les historiques sans fulfillment sont traités par le contrat existant F/PrizesRecord ; les champs source sont indispensables pour auditer les cas ambigus. Aucun moteur actuellement recensé n'émet `fulfillment_type=partner` ; le lecteur Flutter le reconnaît et dirige vers Proxiplay, mais aucun cycle producteur/retireur partenaire autonome n'est démontré.

Absence de `usage_deadline` = aucune expiration technique testée par F. Aucune durée issue des documents juridiques n'a été inventée. Les producteurs plateforme n'écrivent pas de date limite. Le stockage `my_lots` peut initialement ne contenir que `prize_id` : J suit cette référence ; S enrichit ensuite `prize_snapshot`. Le snapshot ne possède pas tous les identifiants de source des producteurs, et peut temporairement présenter un état antérieur au retrait ; V relit le prize transactionnellement avant validation.

Les données historiques sans relation de propriété, avec propriétaire/enseigne contradictoires, mauvais winner ou liens absents n'ont pas été normalisées. Les tests existants couvrent le traitement explicite et le refus de réparation ambiguë. Ce rapport ne mesure pas la fréquence de ces anomalies en production.

### Code de retrait, transversal

| Lot | Générateur / format | Stockage et consultation | Retrait réel | Unicité / expiration / retry |
|---|---|---|---|---|
| Principal marchand | C, crypto 10 octets → 20 hex | prize.claim_code ; J, V, snapshot S | Recherche code V → prize ciblé → transaction claim ; F | Pas de réservation unique ; deadline du jeu ; second claim commerçant refusé |
| Secondaire instant | P, Date.now base36 + crypto 2 octets | Identique | Identique | Pas de réservation ; cache de réponse conserve le même prize/code ; nouvelle transaction avortée n'émet pas de lot durable |
| Animation | A, 8 caractères choisis avec Math.random | prize.claim_code ; J/O ; notification A | Identification et action opérateur O | Pas de réservation ; pas de deadline ; tirage répété ne recrée pas le code |
| Parrainage | D, crypto 5 octets → 10 hex | prize.claim_code ; J/O | O | Pas de réservation ; pas de deadline ; ID prize et tirage idempotents |
| Mensuel | M, Date.now base36 + crypto 2 octets | prize.claim_code ; J/O | O | Pas de réservation ; pas de deadline ; statut du draw verrouille l'attribution |
| Historique / partner | Producteur ancien ou externe non déterminé | Champs présents seulement | V si ownership et fulfillment marchand prouvés ; sinon revue O | Pas de génération rétroactive silencieuse ; pas de cycle partner démontré |

Le code est un **identifiant de recherche/présentation**, pas une autorisation de retirer à lui seul. Un autre commerçant reste refusé même s'il le connaît. Offline : consultation possible selon cache Firestore, mais V utilise une transaction nécessitant le serveur ; aucun retrait offline confirmé n'est implémenté. Si une validation a réussi avant perte de réponse, sa répétition ne doit pas consommer un autre gain : le prize est déjà `claimed`; le second appel commerçant est refusé et l'écran doit être rafraîchi. O peut répéter la mise à jour administrative et ses timestamps, limite distincte décrite en F.

## H. Cas limites et risques de production du cycle

| Cas | Preuve / traitement | Statut |
|---|---|---|
| Double participation / réponse perdue | Cycle instant et classique : un ticket, un gain, même résultat en cache | VERT |
| Changement de jour Paris | Deux appels de part et d'autre de minuit → deux tickets datés distincts | VERT |
| Cron relancé / double tirage | C/A concurrents ; D/M répétés ; scheduled_draw_runner et suites existantes | VERT |
| Transaction interrompue | Instant rollback intégral puis reprise ; autres moteurs dans les tests existants | VERT |
| Joueur supprimé/suspendu | Exclusion avant participation P et tirages C/A/D/M ; pas de prize fantôme | VERT |
| Jeu expiré / annulé / inactif | Dates P existantes ; états inactifs désormais refusés avant instant | VERT |
| Lot expiré / déjà réclamé | Lecture gagnant conservée ; update marchand refusé par F | VERT |
| Date de retrait invalide avant gain | Refus P ou revue C avant attribution ; aucune donnée distante réparée | VERT |
| Mauvais commerçant / mauvais gagnant | Vérifications de lecture et de claim sur les prizes effectivement produits | VERT |
| Historiques sans nouveaux champs | Compatibilité déjà testée ; documents ambigus requièrent revue, inventaire distant inconnu | ORANGE |
| Jeu créé par admin / plusieurs enseignes d'un propriétaire | Fixtures C et animation, propriétaire explicite et visites par enseigne | VERT |
| Panne après acceptation / deux workers | Événement durable, draw bloqué tant que pending, un ticket après reprise | VERT |
| Événement après tirage / ticket contradictoire | Revue Q, pas de modification silencieuse des chances historiques | ORANGE |
| QR sans preuve | from_qr=true suffit ; scénario positif de gain reproductible sans scan | ROUGE |
| Opérateur plateforme / remise physique | Liste et droit d'écriture constatés, stockage testé ; procédure réelle non recettée | ORANGE |
| Code ambigu, snapshot/notification retardé | Pas de contrainte unique, pas de garantie de réception/temps de projection | ORANGE |

Ces contrôles locaux ne démontrent pas l'état READY des indexes, l'activation des crons/triggers, les versions mobiles distribuées ou la présence effective d'une procédure de remise opérateur. Les contraintes déjà documentées de migration C → B ne sont pas réauditées ici.

## I. Recommandations ciblées

1. Définir puis tester la preuve QR serveur avant toute affirmation de contrôle VIP/présence en boutique.
2. Faire une recette opérateur sur les trois familles plateforme : retrouver le gain, identifier le bénéficiaire, organiser la remise, marquer retiré, rejouer la demande et tester une échéance. Décider si un sponsor doit pouvoir retirer un lot mensuel ; le code actuel le réserve à Proxiplay.
3. Définir une identification non ambiguë du lot pour la recherche par code, puis tester les collisions et la coexistence historique. Ne pas réémettre tous les codes historiques sans procédure métier.
4. Prévoir une reprise des effets après commit et une vérification des lots historiques non routés. Aucun backfill automatique ni correction de propriétaire présumée.
5. Conserver les six suites de cycle et exécuter les suites Functions séquentiellement : certains anciens fichiers partagent leur projet d'émulateur. Les tests de la matrice utilisent eux aussi un projet local commun nettoyé entre scénarios.

## J. Verdict et réponses demandées

1. **Classique A → Z : oui, VERT pour le parcours marchand valide démontré localement**, après corrections de clôture/admission/échéance. Les données anciennes ambiguës restent à traiter explicitement.
2. **Instant A → Z : oui, VERT pour le gain marchand**, depuis la planification jusqu'au retrait, incluant perte de réponse et reprise transactionnelle. L'unicité absolue de tous les codes n'est pas démontrée.
3. **QR-only/VIP A → Z : non, ROUGE pour l'admission.** Le gain/retrait fonctionne, la condition de scan ne peut pas être affirmée.
4. **Animations A → Z : ORANGE.** Qualification, attribution, projections, lecture et droit de retrait admin sont démontrés ; recette réelle de remise opérateur et livraison des notifications manquantes.
5. **Parrainage A → Z : ORANGE pour le lot tiré**, VERT pour les droits/crédits testés. La chaîne durable fonctionne ; le lot plateforme conserve la limite opérateur.
6. **Challenges/fidélité : ORANGE pour les lots mensuels**, VERT pour les crédits de position. Les labels VIP/loyalty ne constituent pas une qualification supplémentaire démontrée.
7. **Tous les gagnants ?** Les gagnants nouvellement attribués par les moteurs de lots testés reçoivent atomiquement prize + my_lots, avec code, visibilité joueur et accès du validateur prévu. Cela n'est pas une preuve universelle pour toutes les données historiques, les documents partner externes ou toutes les versions déployées. Les récompenses de crédits/droits ne doivent pas créer de lot matériel.
8. **Un joueur peut-il gagner sans réussir à retirer ?** Oui, un gain historique déjà expiré ou mal rattaché, un lien perdu non repris, ou un lot plateforme sans prise en charge opérateur peut rester sans remise effective. Le code ne garantit pas une intervention humaine. Les nouvelles attributions avec échéance déjà passée sont désormais bloquées avant de déclarer un gagnant ; les données existantes restent inchangées. Une impossibilité définitive même pour un administrateur n'est pas démontrée : les voies de revue/reprise existent mais ne remplacent pas une procédure exécutée.

**VERDICT GAME ENGINE : C — plusieurs cycles incomplets au niveau de la preuve métier A → Z**, principalement l'admission QR/VIP et le dernier kilomètre opérateur des lots plateforme. Les cycles marchands classiques/instants sont démontrés localement après les correctifs ; aucune mise en production n'est autorisée par ce verdict.

## Résultats d'exécution finaux

Les totaux et l'état Git final sont consignés ci-dessous après la dernière exécution.

| Vérification | Résultat |
|---|---|
| Suite Functions utile, tous les fichiers `test/*.test.js` sauf test SMTP exécuté séparément, `--test-concurrency=1` | 327 réussis, 0 échec, 0 ignoré ; 4 suites, environ 152 s |
| Nouveaux scénarios `game_lifecycle_*.test.js` inclus dans cette suite | 28 scénarios de cycle |
| Recontrôle classique après ajout du cas de date malformée | 8 réussis |
| Notifications idempotentes, transport Nodemailer substitué, exécution séparée | 2 réussis ; total Functions distinct : 329 |
| Suite Flutter complète `flutter test --no-pub` | 86 réussis |
| `flutter analyze --no-pub` | 0 erreur ; 24 warnings et 166 infos préexistants, code de sortie 1 |
| TypeScript Functions, `tsc --project firebase/functions/tsconfig.json --noEmit` | Réussi |
| `git diff --check` | Réussi |

La première passe avait reproduit cinq échecs sur les cycles classique/instant (absence de clôture et admission des comptes/jeux invalides). Une première passe élargie a également signalé l'ancien test exigeant que l'animation sans qualifié reste active ; son attente est désormais remplacée par la clôture explicite testée. Les fixtures initiales d'animation/parrainage et de planification ont été ajustées au schéma `threshold`, à l'injection avant chargement du worker, et à la contrainte de génération avant début du jeu. Ces ajustements ne changent pas les règles métier de ces producteurs.

Les fichiers du chantier sont les trois modules applicatifs cités en E, le test d'animation existant, les six nouveaux tests de cycle, leur helper et ce rapport. `HEAD` reste `d35264b91089f5d78ff60df45bc33212c86a43f2` sur `develop`. Les trois fichiers protégés restent hors chantier ; aucun commit/push n'a été effectué.


## Resultats finaux du chantier GAME ENGINE C ? B

Ces resultats remplacent les totaux de l'audit initial ci-dessus.

| Verification | Resultat |
|---|---|
| QR + operateur + cycles plateforme, premiere passe ciblee | 17 reussis ; les cycles plateforme ont ensuite ete reraccordes au callable reel |
| Cycles animation/parrainage/mensuels via callable reel + audit historique | 12 reussis, 0 echec |
| Suite Functions utile, tous les test/*.test.js sauf SMTP isole, execution sequentielle | **335 reussis, 0 echec, 0 ignore**, 4 suites, environ 209 s |
| Controle operateur final, incluant lecture gagnant/admin et refus marchand des lots partner | **4 reussis**, deja comptes dans les 335 |
| Notification idempotente, Nodemailer substitue, test isole | **2 reussis**, aucun envoi reel |
| Total Functions distinct | **337 reussis** |
| Flutter cible : test/game_qr_access_test.dart | **2 reussis** |
| Flutter complet : flutter test --no-pub | **88 reussis**, incluant les 2 tests QR |
| Total distinct Functions + Flutter | **425 tests reussis** |
| flutter analyze --no-pub | **0 erreur, 24 warnings, 166 infos**, aucun nouveau diagnostic par comparaison avec le journal initial ; sortie 1 pour cette dette existante |
| TypeScript Functions : tsc --noEmit | Reussi |
| git diff --check | Reussi ; avertissements de conversion LF/CRLF uniquement |

Les messages PERMISSION_DENIED des tests correspondent aux refus attendus ; les scenarios de panne/referral et notification locale n'impliquent aucun appel de production reussi. Les tests de retrait platform utilisent maintenant claimOperatorPrize via firebase-functions-test ; ce ne sont plus de simples mises a jour Firestore administratives. La matrice couvre 31 scenarios game_lifecycle, plus les 4 contrats de retrait operateur. Aucune nouvelle recette USB, iOS ou de remise physique n'est revendiquee.

Etat final : develop, HEAD d35264b91089f5d78ff60df45bc33212c86a43f2 ; 17e2132 non integre ; fichiers proteges inchanges par ce chantier ; aucun commit/push/deploiement/backfill ni modification de donnees distantes.

**VERDICT GAME ENGINE : B.** QR/VIP VERT dans le perimetre local ; animations, parrainage avec lot et challenges ORANGE tant que l'interface operateur historique n'est pas raccordee au nouveau contrat. Backend de retrait demontre ; conditions de mise en service decrites dans la section courante en tete de rapport.


## Resultats finaux ? raccordement admin du 10 septembre 2026

| Controle | Resultat |
|---|---|
| Suite backend utile complete, sequentielle | **336 reussis, 0 echec** |
| Notifications isolees, Nodemailer substitue | **2 reussis**, aucun email reel |
| Contrats operateur finaux, apres ajout des statuts historiques expire/expired | **5 reussis**, inclus dans le total backend |
| Total backend distinct | **338 reussis** |
| Integration admin reelle (moteurs ? query admin ? SDK ? handler HTTP ? snapshot joueur), controle d'acces UI inclus | **5 reussis, 0 echec** |
| Ancienne suite admin referral-games-api.test.ts | **4 reussis, 1 echec** : DELETE d'un jeu actif repond 200 au lieu de 409, ligne 89 ; fichiers non modifies |
| TypeScript admin, tsc --noEmit --incremental false | Reussi apres regeneration des types Next et retrait d'un validateur dev genere obsolete |
| Lint admin cible | 0 erreur, 12 warnings |
| Flutter complet, flutter test --no-pub | **88 reussis**, dont compatibilite lots et parcours de lancement ; aucun code Flutter change dans ce volet |
| flutter analyze --no-pub | **0 erreur, 24 warnings, 166 infos**, sortie 1 pour diagnostics existants |
| TypeScript backend, tsc --noEmit | Reussi |
| git diff --check mobile et admin | Reussi dans les deux depots ; avertissements LF/CRLF uniquement |

Une premiere passe backend ciblee avait rencontre une transaction d'emulateur fermee pendant le test concurrent de parrainage. Le fichier isole a ensuite passe ses 3 scenarios, puis la suite complete a passe 336 tests sans echec. Les resultats finaux ne masquent pas l'echec distinct et reproductible de l'ancienne API admin de suppression.

### Reproduction locale de l'integration admin

Demarrer Firestore local sur 127.0.0.1:8080 avec les rules du depot et le projet demo-proxiplay-lifecycle, puis Auth sur 9099 pour ce meme projet. Dans le depot mobile, definir GCLOUD_PROJECT=demo-proxiplay-lifecycle, FIRESTORE_EMULATOR_HOST=127.0.0.1:8080, FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099, FUNCTIONS_EMULATOR=true, puis lancer node firebase/functions/test/operator_http_server.cjs. Le serveur refuse tout autre projet ou des emuleurs absents, et refuse FIREBASE_DEBUG_MODE=true pour conserver la verification Auth.

Dans admin-proxiplay, definir NEXT_PUBLIC_FIREBASE_PROJECT_ID=demo-proxiplay-lifecycle, NEXT_PUBLIC_FIREBASE_API_KEY=demo-api-key, NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=demo-proxiplay-lifecycle.firebaseapp.com et PROXIPLAY_MOBILE_ROOT vers le depot mobile ; executer node --import tsx --test --test-concurrency=1 operator-withdrawal.integration.test.ts. Ne pas executer simultanement les suites partageant ce projet : les fixtures effacent son Firestore local. Les comptes Auth de test sont locaux et les connexions SDK sont explicitement dirigees vers les emuleurs.

**Statuts finaux : Animations VERT local ; Parrainage ORANGE global (retrait VERT, suppression active a corriger) ; Challenges VERT local. VERDICT GAME ENGINE : B.** La recette visuelle du bouton dans un navigateur n'est pas automatisee, et le packaging dans le CLI Functions installe reste a verifier apres resolution de son incompatibilite SDK. Aucun test mocke n'est utilise pour affirmer la validation du retrait HTTP.


**Cloture du dernier correctif : suite API admin 7/7 ; Parrainage VERT local ; GAME ENGINE B.** Le defaut de suppression decrit dans les sections historiques est corrige.
