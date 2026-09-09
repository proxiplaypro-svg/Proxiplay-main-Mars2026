# Annexes et preuves — audit du 8 septembre 2026

## Résultats finaux

- Functions, exécution séquentielle locale finale : **233 tests, 226 réussis, 7 ignorés, 0 échec** (dont 2 suites).
- Notifications SMTP, test séparé avec Nodemailer remplacé : **2 réussis, 0 échec**. La séparation est nécessaire : FUNCTIONS_EMULATOR=true supprime volontairement l'envoi et invalide les assertions de ce test.
- Total des tests Functions effectivement réussis : **228** ; sept tests de confidentialité temporairement ignorés.
- Flutter avant et après changements : **80 réussis**.
- `flutter analyze --no-pub` : **0 erreur, 25 warnings, 169 infos** ; commande non verte car 194 diagnostics. Aucun warning nouveau identifié sur les lignes modifiées ; pas de nettoyage global de dette dans cet audit.
- `npm run compile` : succès. JS généré identique en contenu au bundle versionné ; différences de fins de ligne de compilation annulées.
- `git diff --check` : succès.
- Nouveaux tests exécutés sur le code initial : cinq échecs reproduits (quatre tests sécurité et le cas parrainage mixte exclu/admissible), corrigés ensuite.
- Tirage principal : test avec zéro participant, un participant/retry/concurrence, et erreur injectée après mise en attente des écritures ; tous réussis.

Le premier démarrage Firebase CLI n'a pas pu télécharger Firestore 1.22.0 (certificat TLS non reconnu). Firestore 1.21.0 déjà en cache a été lancé localement avec Java 21, langue anglaise (la version en cache rencontrait une erreur interne de localisation en français sur certaines erreurs rules). Auth Emulator a été lancé pour les tests de suppression de compte. Aucun contournement de TLS n'a été appliqué.

Une première suite exploratoire sans Auth présent a échoué sur le setup Auth et sur les deux assertions SMTP sous FUNCTIONS_EMULATOR=true. Une autre exécution a montré deux échecs de fixtures partagées sur la relecture d'un résultat ; le test utilise maintenant son propre projet et réinitialise ses fixtures. La suite séquentielle finale ci-dessus passe. Ces résultats intermédiaires ne sont pas présentés comme des bugs applicatifs.

## Reproduction locale sous PowerShell

Depuis la racine, démarrer Auth et Firestore Emulator (ports 9099/8080), puis :

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:GCLOUD_PROJECT = 'demo-proxiplay-audit'
$env:FUNCTIONS_EMULATOR = 'true'
$auditTests = @(Get-ChildItem firebase/functions/test -Filter '*.test.js' |
  Where-Object { $_.Name -ne 'notify_prize_won_idempotence.test.js' } |
  ForEach-Object { $_.FullName })
node --test --test-concurrency=1 $auditTests
Remove-Item Env:FUNCTIONS_EMULATOR
node --test firebase/functions/test/notify_prize_won_idempotence.test.js
flutter test
flutter analyze --no-pub
```

Le dernier test SMTP intercepte Nodemailer : il n'envoie aucun mail. Les tests de moteurs utilisent des projets démo et effacent leurs fixtures locales ; ne jamais rediriger ces tests vers une base distante. Aucun test UI instrumenté ni test réel FCM/SMTP/Google/Scheduler n'a été réalisé.

## Les 43 commits examinés (ordre chronologique)

```
2ac23d5 Corrige l'affichage et la suppression des lots joueur
96000d9 Rend animations lisible publiquement, comme games/enseignes
55da35a Agrandit la bulle "Offert par" sur les cartes de jeu
ca281d2 Revient aux tailles de texte d'origine dans la bulle "Offert par"
88eb965 Corrige deux plantages en ecran blanc sur le detail d'un lot
2a72d8c Corrige le libelle 'Scanner' errone sur un jeu classique (invite)
c9db605 Bump version to 1.0.27+70
bb00764 Assouplit la contrainte intl pour satisfaire flutter_localizations
516a979 Revert : intl est epingle par le SDK Flutter, pas par pubspec.yaml
28237fa Fusionne les besoins Firestore de proxiplay-admin dans ce fichier
baf53e8 Ajoute l'association Google Place ID cote admin et commercant
f0956cc Reordonne la carte commerce et deplace le Google Place ID vers le secret; recupere la note Google
3f58952 Rapproche le style de la carte commerce du mockup
6f58e4c Corrige la disparition des lots joueur et commercant (regle Firestore isAdmin() + requete commercant)
116c401 Ajoute un script d'audit/reparation des liens my_lots manquants
724ad35 Corrige le compteur "lots a recuperer" a 0 sur le profil joueur
8f65f07 Corrige la validation manuelle de code gagnant cote commercant (home)
2052222 TEMPORAIRE : rouvre la lecture publique de prizes en attendant le prochain build mobile
5893d75 Ajoute un test "contrat de requetes" pour la collection prizes
f18905f Colore la carte "Offert par" et remonte-la sur la fiche jeu joueur
b64c51d Retire la seconde photo de la carte "Offert par", agrandit la premiere
fde470f Ajoute la note Google sur les cartes commerce de l'onglet Commerces
620638f Ajoute le badge "tickets" du joueur sur les cartes de jeu et la fiche jeu
08e9237 Remplace le badge tickets de la fiche jeu par une carte dediee dans Regles
97d603c Corrige une erreur de compilation : import manquant dans jeu_detail_commercant_page_widget.dart
b84bfd0 Retire les puces de categorie de la carte commercant et le fond jaune du badge tickets
ac271f3 N'affiche le badge tickets que sur les jeux avec un lot principal
4d644cc Remplace "Vous avez deja joue" par le nombre de tickets valides sur le bouton principal
ee84707 Corrige l'overflow de la carte "etablissement Google associe"
b8afe90 Bouton dedie et visible pour associer/modifier l'ID Google cote admin
263320f Corrige l'erreur de compilation sur jeu_detail_joueur_page_widget.dart
cc0a6b5 Empeche de re-gratter la carte quand on a deja joue aujourd'hui
2afd3c2 Corrige l'index Firestore manquant et un crash dans generateInstantWinnersForGame
dd821f3 Enregistre l'association Google immediatement au lieu d'attendre "Mettre a jour"
cdf1c8f Evite de tronquer le nombre d'avis Google sur la carte "Offert par"
350b92a Audit : indexes Firestore manquants (users, ff_push_notifications) et cle dupliquee
571aadd Supprime la notification doublon envoyee au commercant sur un gain
76e787a Corrige l'index manquant qui bloquait la validation des comptes commercants
cc6c776 Retire la fonctionnalite de verification d'identite jamais implementee
5cde307 Retire AccountStatus.pendingInfo, egalement jamais ecrit
d3d72af Retire le tirage au sort en double dans autoManageReferralGames
bc461c2 Remove dead drawWinnerForReferralGame (never called)
12bd6aa Add missing composite index for the animations midnight draw
```

## Les 53 fichiers du diff main→develop

```
firebase/firestore.indexes.json
firebase/firestore.rules
firebase/functions/draw_referral_game_winner.js
firebase/functions/google_place_rating_refresh.js
firebase/functions/google_places_details.js
firebase/functions/google_places_search.js
firebase/functions/google_places_search_callable.js
firebase/functions/google_places_secret.js
firebase/functions/index.js
firebase/functions/monthly_challenge.js
firebase/functions/participate_in_game_transaction.js
firebase/functions/prize_my_lots_repair.js
firebase/functions/scripts/audit_my_lots_links.js
firebase/functions/test/firestore_rules_admin_console.test.js
firebase/functions/test/firestore_rules_animations.test.js
firebase/functions/test/firestore_rules_google_place_id.test.js
firebase/functions/test/firestore_rules_prizes_and_my_lots.test.js
firebase/functions/test/firestore_rules_prizes_query_contract.test.js
firebase/functions/test/firestore_rules_users.test.js
firebase/functions/test/google_place_rating_refresh.test.js
firebase/functions/test/google_places_details.test.js
firebase/functions/test/google_places_search.test.js
firebase/functions/test/google_places_search_callable.test.js
firebase/functions/test/lots_joueur_read_path.test.js
firebase/functions/test/prize_my_lots_repair.test.js
lib/auth/firebase_auth/account_routing.dart
lib/auth/firebase_auth/account_routing_logic.dart
lib/backend/backend.dart
lib/backend/google_places/google_place_search_result.dart
lib/backend/schema/enseignes_record.dart
lib/backend/schema/enums/enums.dart
lib/backend/schema/identity_documents_record.dart
lib/components/game_card_widget.dart
lib/components/google_establishment_picker_widget.dart
lib/components/merchant_offered_by_bubble.dart
lib/components/ticket_badge_widget.dart
lib/pages/admin/commercant_admin_detail_page/commercant_admin_detail_page_widget.dart
lib/pages/admin/commercants_admin_page/commercants_admin_page_widget.dart
lib/pages/commercant/add_enseigne_commercant_page/add_enseigne_commercant_page_widget.dart
lib/pages/commercant/home_commercant_page/home_commercant_page_widget.dart
lib/pages/commercant/jeu_detail_commercant_page/jeu_detail_commercant_page_widget.dart
lib/pages/commercant/update_enseigne_commercant_page/update_enseigne_commercant_page_widget.dart
lib/pages/joueur/enseigne_joueur_page/enseigne_joueur_page_widget.dart
lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart
lib/pages/joueur/jeu_detail_joueur_page/jeu_detail_joueur_page_widget.dart
lib/pages/joueur/lot_detail_joueur_page/lot_detail_joueur_page_widget.dart
lib/pages/joueur/lots_joueur_page/lots_joueur_page_widget.dart
lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart
lib/pages/joueur/profil_joueur_page/profil_joueur_page_widget.dart
lib/pages/joueur/share_jeu_page/share_jeu_page_widget.dart
lib/services/google_places_service.dart
pubspec.yaml
test/account_routing_test.dart
```

## Inventaire des fichiers de tests

| Fichier | Cas déclarés détectés |
|---|---:|
| [audit_security_regressions.test.js](../firebase/functions/test/audit_security_regressions.test.js) | 4 |
| [delete_functions_migration.test.js](../firebase/functions/test/delete_functions_migration.test.js) | 8 |
| [draw_animation_winner.test.js](../firebase/functions/test/draw_animation_winner.test.js) | 8 |
| [draw_indexes_contract.test.js](../firebase/functions/test/draw_indexes_contract.test.js) | 2 |
| [firestore_rules_admin_console.test.js](../firebase/functions/test/firestore_rules_admin_console.test.js) | 10 |
| [firestore_rules_animations.test.js](../firebase/functions/test/firestore_rules_animations.test.js) | 6 |
| [firestore_rules_google_place_id.test.js](../firebase/functions/test/firestore_rules_google_place_id.test.js) | 13 |
| [firestore_rules_prizes_and_my_lots.test.js](../firebase/functions/test/firestore_rules_prizes_and_my_lots.test.js) | 21 |
| [firestore_rules_prizes_query_contract.test.js](../firebase/functions/test/firestore_rules_prizes_query_contract.test.js) | 3 |
| [firestore_rules_users.test.js](../firebase/functions/test/firestore_rules_users.test.js) | 13 |
| [game_integrity_audit.test.js](../firebase/functions/test/game_integrity_audit.test.js) | 2 |
| [get_prize_winner_contact_for_merchant.test.js](../firebase/functions/test/get_prize_winner_contact_for_merchant.test.js) | 5 |
| [google_place_rating_refresh.test.js](../firebase/functions/test/google_place_rating_refresh.test.js) | 12 |
| [google_places_details.test.js](../firebase/functions/test/google_places_details.test.js) | 5 |
| [google_places_search.test.js](../firebase/functions/test/google_places_search.test.js) | 5 |
| [google_places_search_callable.test.js](../firebase/functions/test/google_places_search_callable.test.js) | 7 |
| [instant_winners_core.test.js](../firebase/functions/test/instant_winners_core.test.js) | 23 |
| [lots_joueur_read_path.test.js](../firebase/functions/test/lots_joueur_read_path.test.js) | 9 |
| [main_prize_draw_audit.test.js](../firebase/functions/test/main_prize_draw_audit.test.js) | 3 |
| [monthly_challenge.test.js](../firebase/functions/test/monthly_challenge.test.js) | 35 |
| [notify_prize_won_idempotence.test.js](../firebase/functions/test/notify_prize_won_idempotence.test.js) | 2 |
| [participate_already_played_no_parts.test.js](../firebase/functions/test/participate_already_played_no_parts.test.js) | 3 |
| [participate_minor_restricted_games.test.js](../firebase/functions/test/participate_minor_restricted_games.test.js) | 4 |
| [participate_with_monthly_challenge.test.js](../firebase/functions/test/participate_with_monthly_challenge.test.js) | 3 |
| [prize_my_lots_repair.test.js](../firebase/functions/test/prize_my_lots_repair.test.js) | 13 |
| [referral_game_integration.test.js](../firebase/functions/test/referral_game_integration.test.js) | 9 |
| [referral_games_core.test.js](../firebase/functions/test/referral_games_core.test.js) | 4 |
| [scheduled_draw_runner.test.js](../firebase/functions/test/scheduled_draw_runner.test.js) | 3 |
| [account_routing_test.dart](../test/account_routing_test.dart) | 30 |
| [firebase_environment_test.dart](../test/firebase_environment_test.dart) | 10 |
| [game_launch_coordinator_test.dart](../test/game_launch_coordinator_test.dart) | 8 |
| [home_games_logic_test.dart](../test/home_games_logic_test.dart) | 12 |
| [minor_restricted_game_access_test.dart](../test/minor_restricted_game_access_test.dart) | 5 |
| [startup_config_flow_test.dart](../test/startup_config_flow_test.dart) | 2 |
| [user_profile_completion_test.dart](../test/user_profile_completion_test.dart) | 7 |

Les nombres du tableau comptent les déclarations lexicales, pas les cas générés ni les sous-tests ; les totaux exécutés en tête font foi.
