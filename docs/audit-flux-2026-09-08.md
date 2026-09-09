# Inventaire préalable des flux — 8 septembre 2026

Base examinée avant correction : develop `12bd6aa`, main `48cd073`, **43 commits** exclusifs (et non 33). Aucun accès production ni réparation historique. Le fichier local préexistant `firebase/functions/rapport_repair.json` n'est pas modifié.

| Mécanique | Entrée / création / activation | Participation et qualification | Attribution | Lecture / utilisation |
|---|---|---|---|---|
| Classique, lot principal | `add_game_commercant_page`: document `games`, liaison `enseignes/.../enseigne_game`; fenêtre start/end | callable `participateInGameTransaction`; `participants/{jourParis_uid}`, `participants_details/{uid}`, `unique_players/{uid}`, compteur utilisateur | `pickMainPrizeWinners`, minuit Paris; transaction game + prize auto-ID + my_lots même ID | listes games; lots joueur via my_lots puis get prize; retrait Flutter met claimed=true |
| Instantané | même création puis callable `generateInstantWinnersForGame`; sous-collection `instant_winners` | même participation, créneau échu le plus récent; anciens créneaux expirés | transaction participation + créneau + prize + my_lots | mêmes lecteurs; notifyPrizeWon à la création du prize |
| Bonus fidélité | intégré à la participation | chaque dixième participation **globale au jeu** | +3 remaining_part; aucun prize attendu | solde joueur; ce ne sont pas trois tickets déjà validés |
| QR / VIP | `access_mode=qr_only`; lancement par lien/QR; allGamesAccessUntil | from_qr booléen déclaré par client; accès illimité supprime le débit de parties, pas la limite jeu/jour | moteurs classiques | pas de moteur de lots VIP indépendant repéré |
| Parrainage classique | createReferral, code; registerReferralAcceptance | refus auto-parrainage / second filleul; referrals accepted | sans jeu actif : reward_events + avantage utilisateur via share_promo | état parrainage, pas nécessairement un lot physique |
| Jeu de parrainage | referral_games draft; autoManageReferralGames toutes les 15 min; admin externe | acceptance puis addReferralGameTicket, entry ID=referralId | drawReferralGameWinner minuit Paris / adminDrawReferralGameWinner; moteur referral_game_engine; prize déterministe + my_lots + état | carte/detail referral; lot générique; admin externe non présent |
| Animation | animations + games.animation_id; admin externe | participation classique suit enseignes distinctes, entries/{uid}.threshold_reached | drawAnimationWinners minuit Paris; winner/current + winner_uid + prize animation_ID + my_lots dans transaction | animation_detail lit aussi winner/current; lot générique; remise organisée par Proxiplay |
| Assiduité mensuelle | adminUpsertMonthlyChallenge, monthly_challenges + configuration legacy | participation suit jours Paris, état utilisateur et monthly_challenge_entries; objectif gelé | drawMonthlyChallengeWinner chaque jour 01h Paris si draw_date atteinte / adminRunMonthlyChallengeDraw; draw + état + prize déterministe + my_lots | callable d'état, bannières, statistiques admin Flutter, lot générique |
| Restaurant/commerçant du mois | même configuration, type merchant, alias restaurant | même compteur de jours de participation que l'assiduité | même moteur mensuel; type du lot monthly_challenge | bannière commerçant + lot générique, pas de circuit de retrait commerçant spécifique dans le payload |

Les scripts `prize_my_lots_repair.js` et `scripts/audit_my_lots_links.js` ne couvrent que le sens prize→lien canonique absent. La suppression volontaire d'un lien joueur est indiscernable d'une perte technique. Les réparations restent à examiner individuellement.

Cet inventaire décrit les chemins appelés, pas une validation de fonctionnement. Le rapport associé détaille preuves, défauts, tests exécutés et actions externes.
