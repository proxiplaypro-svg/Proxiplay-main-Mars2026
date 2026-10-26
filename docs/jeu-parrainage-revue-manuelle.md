# Jeu de parrainage — revue manuelle des récompenses

Procédure pour les situations exceptionnelles où un parrainage validé pendant un
jeu de parrainage n'a pas pu recevoir son ticket automatiquement.

## Fonctionnement normal (rappel)

1. À la création du compte du filleul, l'acceptation choisit le jeu actif à la
   date d'acceptation via le verrou `app_config/referral_game_active`
   (`referral_game_lock.js`). Sans jeu utilisable : récompense classique.
2. Elle crée l'événement durable `referral_reward_pending/{parrainage}` (mode
   `game`) et incrémente `pending_reward_count` sur le jeu, dans la même
   transaction.
3. Le traitement immédiat, puis `retryReferralRewards` toutes les 10 minutes,
   créent le ticket `referral_games/{jeu}/entries/{parrainage}` et
   décrémentent le compteur.
4. Le tirage (`drawReferralGame`) attend tant qu'un événement du jeu est
   `pending` ou `manual_review_required`, ou que `pending_reward_count` > 0.

## Quand une revue est nécessaire

Un événement passe en `manual_review_required` (journal
`REFERRAL_REWARD_MANUAL_REVIEW`, champ `reason`) :

| `reason` | Signification | Décision attendue |
|---|---|---|
| `draw_already_finalized` | Le jeu a été tiré avant le traitement (tirage manuel anticipé) | Compensation hors jeu (le tirage passé n'est jamais modifié) |
| `acceptance_outside_period` | Dates du jeu modifiées après l'acceptance | Vérifier les dates ; créer le ticket si l'acceptation était bien dans la période |
| `invalid_source` | Jeu ou parrainage supprimé, parrain différent | Enquête ; aucun ticket sans source valide |
| `contradictory_ticket` | Un ticket existe déjà pour ce parrainage avec un autre parrain | Enquête ; ne jamais écraser |
| `inviter_ineligible` | Parrain supprimé, rejeté ou suspendu | Aucun ticket (règle d'exclusion) |

Un jeu dont un événement est en revue **ne peut pas être tiré** : le tirage
renvoie `unresolved_referral_rewards` jusqu'à la résolution.

## Procédure

1. Lister les cas (lecture seule) : `rollback-1.1.2/tools/referral_pending_check.js`
   ou la collection `referral_reward_pending` filtrée sur
   `status == manual_review_required`.
2. Pour chaque cas, décider selon le tableau ci-dessus, avec trace écrite
   (date, auteur, décision).
3. Ticket dû et jeu non tiré : corriger la cause (dates, données), puis remettre
   l'événement à `pending` : le traitement suivant (au plus 10 minutes) crée le
   ticket une seule fois. Tant que le jeu est actif, `adminReconcileReferralGameTickets`
   peut aussi recréer les tickets manquants de la période.
4. Aucun ticket dû : passer l'événement à `dismissed` avec la raison.
5. Une fois tous les événements du jeu résolus, le tirage planifié suivant
   (minuit Europe/Paris) s'exécute ; un tirage manuel reste possible depuis
   l'Admin.

Ne jamais modifier un jeu déjà tiré, ni supprimer un ticket existant.

## Un seul jeu actif

Le déclencheur `enforceSingleActiveReferralGame` remet en brouillon tout jeu
activé alors qu'un autre détient le verrou (champ `activation_refused_reason:
another_active_game`), quel que soit l'auteur (Admin, console, automate). Pour
changer de jeu : terminer l'actuel (statut `ended` ou `draft`), puis activer le
suivant.
