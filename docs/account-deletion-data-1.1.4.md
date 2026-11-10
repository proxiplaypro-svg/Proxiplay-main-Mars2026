# Suppression des comptes joueurs — ProxiPlay 1.1.4

Statut au 10/11/2026 : corrections faites et testées en local. Rien n'est
poussé ni déployé, et aucune donnée de production n'a été écrite. Les
comptages de production cités ici sont anonymes (agrégats `count()`).

## 1. Suppression depuis l'app

| Avant | 1.1.4 (`7e7a185`) |
|---|---|
| Quand Firebase exigeait une connexion récente : message en anglais, puis renvoi vers la connexion. Le joueur pouvait croire son compte supprimé. | Réauthentification avec le mode de connexion du compte (mot de passe, Google ou Apple), puis une seule nouvelle tentative. |
| Toute autre erreur (réseau…) était ignorée de la même façon. | Annulation, identifiants refusés ou échec : un message en français indique que le compte **n'a pas été supprimé**. |
| — | Le joueur n'est renvoyé vers la connexion qu'après une suppression confirmée par Firebase, ou s'il choisit « Me reconnecter » (déconnexion, puis connexion). |

Hors périmètre : le changement d'e-mail affiche toujours un message en
anglais (« Too long since most recent sign in… »), dans
`firebase_auth_manager.dart`.

## 2. Données d'un compte après sa suppression

« Avant » décrit le comportement de `onUserDeleted` jusqu'à la 1.1.3.
« 1.1.4 » décrit celui de `cleanupDeletedUserData` (`45791f1`), commun à la
suppression par le joueur et à celle par l'Admin.

| Donnée | Avant | 1.1.4 | Nature | Décision |
|---|---|---|---|---|
| Compte Firebase Auth | supprimé (joueur) ; **conservé** (bouton Admin) | supprimé dans les deux cas | identifiants | — |
| `users/{uid}` | supprimé | supprimé | profil | — |
| `users/{uid}/fcm_tokens` | **conservé** | supprimé | jeton de l'appareil | Correctif : les notifications « à tous » lisent tous les jetons (`collectionGroup`), donc un joueur supprimé qui avait gardé l'app pouvait continuer à les recevoir. |
| `notifications`, `favorite_games`, `favorite_enseignes`, `my_enseignes`, `private/share_state` | **conservés** | supprimés | préférences, historique | Aucune valeur de preuve. |
| `birthday_corrections` | — | supprimé | journal d'administration | Ne contient aucune date (voir `birthday-lock-1.1.4.md`). |
| `marketing_consent_events` | conservé | **conservé**, horodaté `account_deleted_at` | preuve de consentement et de retrait | **D1** |
| `my_lots` | conservé | conservé | copie des lots gagnés | **D2** |
| `monthly_challenges` et `monthly_challenge_entries` | conservés | conservés | participation au défi du mois | **D3** |
| `prizes` (`winner_id`) | conservé | conservé | lot gagné, remise par le commerçant | **D4** |
| `public_prize_winners`, champs `winner_first_name` / `winner_city` des jeux | conservés | conservés | **publics** : prénom et ville du gagnant | **D5** |
| `games/{id}/participants`, `participants_details` | conservés | conservés | historique de participation, anti-fraude | **D6** |
| `referrals`, `referral_reward_pending`, `reward_events` (`inviter_uid`) | conservés | conservés | comptabilité des récompenses | **D6** |
| `_referral_email_registry` | conservé | conservé | empreinte HMAC de l'e-mail | déjà décidé : 2 ans |
| `_ad_exposures`, compteurs de publicité | conservés | conservés | empreinte salée, expiration courte | — |
| `admin_account_deletions` | — | créé à chaque suppression par l'Admin | journal d'administration | **D7** |
| Fichiers Storage du joueur | non audité | non audité | photo éventuelle | À vérifier : `photo_url` provient surtout de Google. |

## 3. Stratégie pour les preuves de consentement (D1)

**Aujourd'hui.** `setMarketingConsent` fixe `retention_until` à 3 ans après
la création de chaque événement. Le mémo `marketing-consent-privacy-memo.md`
prévoit une purge future, après validation de la durée par le conseil
juridique. Aucune purge ni politique de durée de vie (TTL) n'est en place,
et la 1.1.4 n'en ajoute pas.

**Le défaut.** Une purge fondée sur ce `retention_until` effacerait au bout
de 3 ans la preuve d'un consentement **toujours actif**. Un joueur inscrit
depuis plus de 3 ans n'aurait plus de preuve de son accord, alors que les
envois continueraient.

**Proposition, à valider juridiquement.** Faire partir la durée de la fin
de la relation, pas de la création de l'événement.

1. Tant que le compte existe, conserver tous les événements. Au minimum,
   conserver le dernier événement « granted » tant que le consentement est actif.
2. Après un retrait, conserver l'événement de retrait et l'accord qui le
   précède pendant N années à partir du retrait.
3. Après la suppression du compte, conserver les événements pendant N
   années à partir de `account_deleted_at`. Ce champ est posé par la 1.1.4.
4. Une fois N validé, purger avec une tâche planifiée qui fonctionne d'abord
   en simulation (« dry-run ») et ne supprime que les événements dont l'échéance,
   recalculée selon ces règles, est passée. Ne pas activer de TTL sur le
   `retention_until` actuel.

**À trancher par le juriste.** La valeur de N. Pistes à faire confirmer,
sans les retenir d'office :
- 3 ans, durée de référence de la CNIL pour la prospection ;
- 5 ans, durée de prescription de droit commun.

Il faut aussi confirmer qu'une preuve qui ne contient que l'identifiant
technique, sans e-mail, suffit une fois le compte supprimé.

## 4. Suppression depuis l'Admin

| Avant | 1.1.4 |
|---|---|
| `deleteDoc(users/{uid})` depuis le navigateur, après un simple « Confirmer ? ». | Panneau qui explique ce qui est supprimé et conservé, avec motif obligatoire et saisie de « SUPPRIMER » (Admin `87953cf`). |
| Le compte Auth restait actif : à la connexion suivante, l'app recréait la fiche, avec une nouvelle date de naissance. | Callable `adminDeletePlayerAccount` (`a3cffe2`) : elle supprime d'abord le compte Auth, puis les données, avec le même module que la suppression par le joueur. |
| Aucune trace. | Journal `admin_account_deletions` : identifiant technique, administrateur, motif, statut. Aucune donnée de profil. Lecture réservée aux administrateurs. |
| Les règles autorisaient la suppression de `users/{uid}` par le joueur et par l'Admin. | Plus aucune suppression client de `users/{uid}` : la suppression passe par Auth ou par les callables serveur. |

Garde-fous :
- jamais un compte administrateur (rôle, droit `admin` ou e-mail de la console) ;
- jamais un commerçant : il a sa propre suppression, `deleteCommercantAccount` ;
- jamais son propre compte.

Elle gère aussi :
- une fiche orpheline, sans compte Auth ;
- un compte Auth dont la fiche a déjà été effacée par l'ancien bouton.

## 5. Statistiques : 1 744 joueurs et 1 753 dates de naissance

Les deux nombres ne portent pas sur le même ensemble de comptes.
Comptages anonymes du 10/11 :

| Comptage | Valeur |
|---|---|
| Documents `users` | 1 882 |
| `user_role == "joueur"` | 1 744 |
| `user_role == "commercant"` | 74 |
| `user_role == "admin"` | 2 |
| `user_role` absent ou non texte | 62 (1 882 − 1 820) |
| Ancien champ `userRole` (joueur, commercant, admin) | 0 |
| `birthday` de type horodatage, **tous rôles confondus** | 1 753 |
| `birthday` sous forme de texte | 0 |

- **1 744** compte les seuls documents dont le rôle est « joueur ».
- **1 753** compte toutes les dates de naissance, quel que soit le rôle,
  y compris les comptes sans rôle.

Au moins 9 dates appartiennent donc à des comptes qui ne sont pas des
joueurs. Le nombre réel est de 9, plus le nombre de joueurs sans date.

L'origine la plus probable est la suivante. Les 62 comptes sans rôle, ou
d'anciens joueurs devenus commerçants, ont une date. L'app n'en enregistre
pas pour un commerçant, mais n'efface pas une date existante. C'est une
hypothèse, non vérifiée.

Le croisement exact rôle × date exige un index composite
(`user_role`, `birthday`). Le créer modifierait la configuration de
production, donc ce n'est pas fait. Une autre piste serait un comptage
serveur agrégé, sans lecture individuelle, à prévoir dans les statistiques
Admin.

## 6. Décisions restantes

- **D1. Preuves de consentement.** Fixer N et le point de départ (voir §3),
  puis mettre en place la purge planifiée. D'ici là, ne rien supprimer.
- **D2. `my_lots`.** Le supprimer avec le compte ? Les contrôles
  d'intégrité des lots (`prize_integrity.js`, `prize_lot_snapshot.js`) lisent
  ce lien : il faudrait les adapter avant toute suppression. La référence
  reste `prizes`.
- **D3. Défi du mois en cours.** Un compte supprimé doit-il sortir du
  tirage ? Recommandation : oui, en supprimant `monthly_challenges` et en
  excluant les comptes inexistants au moment du tirage.
- **D4. Lots (`prizes`).** Pendant combien de temps conserver le lien
  `winner_id` après la suppression ? Il sert à la remise par le commerçant
  et aux litiges. Une anonymisation à l'échéance est possible.
- **D5. Gagnants publics.** Le prénom et la ville d'un compte supprimé
  restent affichés publiquement. Recommandation : afficher « Un joueur »
  sans ville dès la suppression, sauf si le règlement des jeux impose de
  publier les gagnants.
- **D6. Participations et parrainages.** Durée de conservation des
  données liées à l'identifiant technique (anti-fraude, comptabilité).
- **D7. Journal des suppressions Admin.** Durée de conservation de
  `admin_account_deletions`. Proposition à valider : 3 ans.
- **D8. Comptes Auth orphelins.** Les comptes Auth dont la fiche a été
  effacée par l'ancien bouton Admin existent peut-être encore. Les recenser
  demanderait de lister les comptes Auth, ce qui est une lecture de données
  individuelles : à autoriser explicitement.

## 7. Ordre de déploiement

À intégrer au plan de `birthday-lock-1.1.4.md`. Chaque étape fait l'objet
d'une validation séparée.

1. Déployer les fonctions `adminDeletePlayerAccount` (nouvelle) et
   `onUserDeleted` (nouveau corps). Comparer d'abord l'archive déployée de
   `onUserDeleted`.
2. Déployer l'Admin (`feat/admin-player-deletion`, qui contient la
   correction de date de naissance). L'ancien bouton disparaît.
3. Déployer les règles Firestore : `users` n'est plus supprimable par
   aucun client. Une console Admin plus ancienne, encore ouverte, verrait
   son bouton refusé, sans perte de données.
4. Publier l'app 1.1.4 : réauthentification et messages en français.
