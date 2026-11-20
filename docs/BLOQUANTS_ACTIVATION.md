# Bloquants avant activation LIVE du parcours de souscription (CGV V2.1)

L'interrupteur `app_config/merchant_contracts.enabled` reste à `false` en
production tant qu'un seul point de cette liste n'est pas levé. La tranche 1
(demande, vérification manuelle, alertes, confirmation, origine) ne doit
jamais être activée seule : un contrat confirmé n'aurait ni invitation à
payer, ni rétractation.

## Bloquants

1. **Tranche 2 complète et testée**. Sous-tranche 2a faite (branche
   `phase1-t2a`) : invitation à payer et lien de 15 jours (1.6), Checkout au
   clic par enseigne (1.7), webhook des contrats (1.8), rétractation (1.5).
   Sous-tranche 2b-1 faite (branche `phase1-t2b`) : tâches planifiées 1.9
   (`merchantContractSchedule`, 2e génération, toutes les heures, Europe/Paris)
   et fins de contrat 1.12 (`disableMerchantRenewal`, `adminRefundRenewal`,
   `adminEndContract`). Restent (2b-2) : statuts 1.14, compteur Accompagnée
   1.15-min.
   **Contrainte du lot 1.9 (décision du 20 novembre 2026)** : la clôture à
   15 jours (`payment_invited` → `closed_unpaid`) n'a lieu qu'après
   l'expiration de la dernière session Checkout ouverte du contrat (relue
   chez Stripe : `status` = `expired` ; une session `open` ou `complete`
   fait attendre), jamais à la seule fin du lien. Fait dans le lot 1.9. Une session peut durer jusqu'à 31 minutes après la fin
   du lien (marge acceptée) ; un paiement fait dans cette marge doit activer
   le contrat et non être remboursé.
2. **Essais Stripe réels (mode TEST)** : ceux de la sous-tranche 2a ont été
   lancés par le propriétaire le 20 novembre 2026 et sont conformes (course,
   facture ouverte, avoir, session Checkout). Restent ceux du lot 1.12 (point
   14) et les événements réels du webhook au format 2026-10-28.endive.
3. **PDF daté des CGV V2.1** : publié le jour effectif de la mise en
   production, archivé, déposé dans Cloud Storage (bucket par défaut) au
   chemin `cgv.storage_path`, avec `version`, `sha256` et `url` dans
   `app_config/merchant_contracts.cgv`. Sans lui, aucune demande n'est
   acceptée et aucune confirmation ne part (`cgv_not_configured`,
   `cgv_pdf_mismatch`). Le lien « Conditions générales de vente » du site
   pointe aujourd'hui vers un PDF absent.
4. **Suppression d'une enseigne liée à une demande ou à un contrat** : la règle
   Firestore actuelle permet au propriétaire de supprimer son enseigne depuis
   l'app (`enseignes` : `allow delete` si `ownsShopData`). La règle n'est pas
   modifiée dans la tranche 1 (elle concerne l'app mobile). La confirmation
   vérifie que l'enseigne existe et appartient au demandeur ; une suppression
   après confirmation laisse un contrat sans enseigne. À traiter avant
   l'ouverture (règle, suppression côté serveur ou release de l'app).
5. **Vérifications Stripe** (lot 0.11) : relances sur 3 semaines, action
   finale « marquer impayé », ne pas annuler les paiements à confirmer,
   portail (annulation d'un abonnement impayé, art. 9), lien
   d'authentification bancaire, pied de facture ; endpoint TEST à la version
   d'API de LIVE.
6. **Codes promotionnels** : la tranche 1 tient le miroir Firestore
   `promo_codes` ; la création du code Stripe correspondant (sens unique,
   Firestore vers Stripe, par une fonction serveur) relève de la tranche 2.
   Aucun code ne doit être créé ou modifié à la main dans Stripe.
7. **Règles Firestore déployées** : les règles des nouvelles collections sont
   dans `firebase/firestore.rules` du dépôt canonique. La console admin a son
   propre `firestore.rules`, non modifié. Il faut établir lequel est déployé
   (lot 0.2) avant tout déploiement, sinon les nouvelles collections
   resteraient fermées (refus par défaut) ou, pire, une ancienne version
   écraserait les règles.
8. **Configuration** (levé dans la tranche 1, correction) : l'outil admin
   `adminUpdateMerchantContractsConfig` (console, page Souscriptions) écrit
   `app_config/merchant_contracts` avec validation, contrôle du PDF dans
   Storage et journal (`merchant_contracts_config_log`). L'interrupteur ne
   coupe que les fonctions côté commerçant et la confirmation ; les fonctions
   admin (commerciaux, liens, codes, vérification, refus, alertes) restent
   utilisables pour préparer l'ouverture. Reste à faire : poser la
   configuration réelle le jour de l'ouverture.
9. **Vérifications non faites sur un service réel** : lecture du PDF dans
   Cloud Storage (remplacée dans les tests), envoi SMTP réel des e-mails de la
   tranche (remplacé dans les tests), tâche planifiée `merchantContractAlerts`
   déclenchée par Cloud Scheduler, requêtes Firestore en production (index
   simples supposés suffisants : `owner_uid` + `state`, `enseigne_id` +
   `state in`, `siret`).
10. **Adresse des alertes** : à fournir par le propriétaire, puis à poser
    avec l'outil de configuration (`admin_alert_email`) ; à défaut, les
    alertes partent à contact@proxiplay.fr.

11. **Avoirs** : option `credit_notes_enabled` (outil de configuration),
    désactivée par défaut, à activer après validation du comptable.
12. **Secret Stripe** : `reportMerchantVisit`, `withdrawMerchantContract` et
    `adminRecordWithdrawal` déclarent désormais `STRIPE_SECRET_KEY` (expiration
    de session, remboursement) : à vérifier au déploiement.
13. **E-mail Stripe d'authentification bancaire** : à activer dans le Dashboard
    (décision 8) ; ProxiPlay n'envoie rien pour ce cas.
14. **Essais Stripe du lot 1.12** (script `essais-2b.cjs`, à lancer par le
    propriétaire) : désactivation dans l'heure, course avec un prélèvement,
    void pendant la grâce, remboursements partiels (avoir et direct),
    résiliation pour impayé (facture ouverte sans nouvelle tentative après
    annulation : non vérifié), `cancel_at_period_end` à l'échéance.
15. **Portail client Stripe** : annulation d'abonnement à désactiver dans le
    Dashboard (décision 7). Une annulation par le portail ne passerait pas par
    la procédure de l'art. 9 ; le webhook terminerait seulement le contrat
    (motif `stripe_canceled`).
16. **Tâche planifiée de 2e génération** : le déploiement exige les API Cloud
    Scheduler et Cloud Run du projet, et le secret `STRIPE_SECRET_KEY` pour la
    lecture des sessions avant clôture. À vérifier au déploiement.
17. **Interrupteur coupé après l'ouverture** : les tâches planifiées et le
    bouton « Désactiver le renouvellement » deviennent inertes. Des rappels
    J-45 seraient alors manqués (remboursement art. 9 ouvert) et le
    commerçant ne pourrait plus désactiver en ligne. Ne pas couper
    l'interrupteur tant qu'un contrat est actif, ou traiter ces cas à la main.

## Décisions prises (19 novembre 2026)

- Jours ouvrés : lundi à vendredi, hors les 11 jours fériés de France
  métropolitaine, lundi de Pentecôte compris.
- Remise de première année plafonnée pour laisser au moins 1 € HT.
- Adresse des alertes : configurable dans `app_config/merchant_contracts`.

## Décisions prises (20 novembre 2026)

- Session Checkout : jusqu'à 31 minutes après la fin du lien (minimum
  Stripe de 30 minutes plus une minute de marge).
- Remboursement automatique d'un paiement initial par le webhook seulement si
  le contrat existe et est `closed_unpaid`, `withdrawn`, `refused`, `ended`,
  `withdrawal_pending`, ou actif avec un autre abonnement. Contrat inconnu,
  enseigne différente, `submitted` ou `confirmed` : aucune action sur
  l'argent, trace (`stripe_unmatched_events`) et alerte ; décision manuelle.
- Tout événement Stripe non rattaché à un contrat ou à un abonnement suivi
  est tracé et alerté au lieu d'être ignoré.
- Clôture à 15 jours (lot 1.9) après l'expiration de la dernière session
  Checkout ouverte.
