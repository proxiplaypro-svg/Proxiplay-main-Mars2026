# Date de naissance verrouillée — ProxiPlay 1.1.4

Statut au 10/11/2026 : implémenté et testé en local. Rien n'est poussé ni
déployé, et aucune donnée de production n'a été écrite.

## Règles de gestion validées

1. La date est verrouillée dès le premier enregistrement confirmé.
2. Le joueur peut la consulter, mais ne peut plus la modifier.
3. Un administrateur habilité peut la corriger via une fonction serveur.
   L'habilitation suit `isTrustedAdmin`, le même critère que `isAdmin()`
   dans les règles Firestore.
4. Chaque correction exige un motif et laisse une trace.
5. Pas de justificatif systématique, pas de plafond de corrections.
6. Si la correction place le joueur sous 15 ans, son consentement marketing
   est retiré, de façon tracée.
7. Les restrictions d'âge sont réévaluées dès l'appel suivant.
8. Aucun lot déjà gagné n'est annulé.
9. La suppression de compte reste possible par le parcours prévu.

## Commits

| Dépôt | Commit | Contenu |
|---|---|---|
| mobile (`release/proxiplay-1.1.4`) | `ffdaa3f` | Règles Firestore : verrouillage de la date, suppression du document réservée aux administrateurs, journal des corrections en lecture admin |
| mobile | `3d71aac` | Fonction `adminCorrectPlayerBirthday`, et suppression du journal des corrections par `onUserDeleted` |
| mobile | `e3d0c4f` | App : date en lecture seule, confirmation à la première saisie, date jamais renvoyée une fois enregistrée |
| Admin (`feat/player-birthday-correction`, dossier `wt-admin-birthday`, issu de `b60697c`) | `fe9d6ff` | Fiche joueur : correction avec motif, et historique des corrections |

## Données conservées (RGPD)

- **`users/{uid}.birthday`** reste la seule copie de la date.
- **Journal `users/{uid}/birthday_corrections`.** Il contient :
  - l'administrateur, la date de correction et le motif (200 caractères maximum) ;
  - les tranches d'âge avant et après : moins de 15 ans, 15 à 17 ans, 18 ans et plus ;
  - s'il y avait déjà une date ;
  - si le consentement marketing a été retiré.

  Il ne contient ni l'ancienne ni la nouvelle date. Seuls les
  administrateurs peuvent le lire, et personne ne peut y écrire depuis un
  client. Il est supprimé avec le compte, par `onUserDeleted`.
- **Motif.** L'Admin demande de n'y mettre ni date, ni pièce justificative,
  ni autre donnée personnelle.
- **Retrait du consentement marketing.** Il ajoute un événement
  `marketing_consent_events` (`withdrawn`, `birthday_correction_under_15`),
  avec la même durée de conservation que les autres événements (3 ans,
  champ `retention_until`).

## Compatibilité

- **Anciennes versions de l'app (1.1.3 et avant).** Elles renvoient la date
  enregistrée à chaque validation du formulaire d'informations. Une valeur
  identique n'est pas considérée comme modifiée, donc la mise à jour passe.
  C'est couvert par un test. Seule une tentative de changer la date est
  refusée, avec le message d'erreur générique de la page. Cette page ne se
  rouvre que pour un profil incomplet ou une date vide.
- **Comptes de production** (comptages anonymes du 10/11) :
  - 1 744 joueurs ;
  - 1 753 dates de naissance, toutes au format horodatage : aucune sous forme de texte, aucune avant 1900, aucune dans le futur ;
  - 22 comptes de moins de 15 ans, 41 de moins de 18 ans ;
  - 2 consentements marketing actifs ;
  - 165 cadeaux d'anniversaire distribués.
- **Comptes sans date.** Ils peuvent encore la saisir une fois.
- **Suppression du compte.** L'app passe par Firebase Auth
  (`currentUser.delete()`), puis `onUserDeleted` efface le document avec le
  SDK Admin. Le joueur ne supprime jamais son document directement : la
  restriction de `delete` aux administrateurs ne touche pas ce parcours.

## Tests (Node 22.23.4, émulateurs)

| Suite | Résultat |
|---|---|
| `firestore_rules_users_birthday` (nouveau) | 11/11 sur les nouvelles règles ; 7 échecs sur la copie des règles de production, ce qui prouve que les failles y sont présentes |
| Tous les tests de règles | 173/173 |
| `player_birthday_correction` (nouveau) | 10/10 |
| Suite complète des Functions | 903/903 |
| `flutter test` | 729/729 |
| `flutter analyze` | 0 erreur, aucun nouveau signalement |
| Admin : `player-birthday.test.ts` | 4/4 |
| Admin : `tsc` | aucune erreur |
| Admin : `eslint` | aucune erreur |
| Admin : `next build` | réussi |

## Plan de déploiement

Chaque étape fait l'objet d'une validation séparée. On déploie depuis
`Proxiplay-release-1.1.4`, jamais depuis `Proxiplay-develop`, qui contient
`.env.local`.

**Avant de commencer**

1. Pousser les branches, avec revue.
2. Relire les règles en production et les comparer à `firestore.rules`
   avant `ffdaa3f`, c'est-à-dire au commit `50d26db`. Le 10/11, l'écart était
   nul : ruleset `d56f993d…`, publié le 08/11 à 21:56 UTC. S'il y a un écart,
   l'intégrer d'abord.
3. Identifier l'arbre réellement en production pour l'Admin
   (`vercel inspect`), puis rebaser `feat/player-birthday-correction`
   dessus si ce n'est plus `b60697c`.

**Étape 1 — Nouvelle fonction `adminCorrectPlayerBirthday`.**
- Commande : `firebase deploy --only functions:adminCorrectPlayerBirthday`.
- Impact : aucun, tant que personne ne l'appelle.
- Retour arrière : supprimer cette nouvelle fonction uniquement.

**Étape 2 — `onUserDeleted`, depuis la 1.1.4.**
- Elle doit être déployée avant la première correction, pour que le journal
  soit supprimé avec le compte.
- Comparer d'abord l'archive déployée de la fonction avec la 1.1.4, comme
  pour les autres groupes Node 22, pour mesurer tout ce qui change.
- Retour arrière : redéployer depuis le commit source précédent.

**Étape 3 — Admin.**
- Déploiement Vercel depuis la branche rebasée.
- Test avec un compte joueur de test : correction, historique, motif obligatoire.
- Retour arrière : `vercel rollback`.

**Étape 4 — Règles Firestore.**
- Commande : `firebase deploy --only firestore:rules`, depuis la 1.1.4,
  seulement si la comparaison du point 2 est toujours nulle.
- Contrôles juste après, avec un compte de test :
  - sur une version 1.1.3, valider le formulaire sans toucher à la date : doit passer ;
  - changer la date par un appel direct : doit être refusé ;
  - supprimer le document joueur : doit être refusé ;
  - corriger la date depuis l'Admin : doit passer.
- Retour arrière immédiat : republier le ruleset `d56f993d-64d6-44c3-ab00-e4084ae4ba7c`.

**Étape 5 — App 1.1.4 sur les stores.**
- Elle affiche la date en lecture seule et demande une confirmation à la
  première saisie.

**Suivi**
- Journaux de `adminCorrectPlayerBirthday`.
- Nombre de documents `birthday_corrections`.
- Nombre de cadeaux d'anniversaire par jour : il devrait baisser s'il y
  avait des abus.

## Points relevés, hors périmètre

- **Échec de suppression non signalé.** Dans l'app, si Firebase exige une
  connexion récente pour supprimer le compte, le message s'affiche en
  anglais et le joueur est quand même renvoyé vers la connexion. Il peut
  croire son compte supprimé alors qu'il ne l'est pas.
- **Sous-collections orphelines.** `onUserDeleted` ne supprime pas
  `favorite_games` ni `marketing_consent_events`. Pour ces derniers,
  `retention_until` prévoit une conservation de 3 ans comme preuve, mais
  aucune politique TTL n'est configurée. À décider.
- **Suppression depuis l'Admin.** « Supprimer ce joueur » efface le
  document `users`, mais pas le compte Auth ni les sous-collections. À la
  reconnexion, l'app recrée un profil, et la date peut alors être saisie de
  nouveau.
