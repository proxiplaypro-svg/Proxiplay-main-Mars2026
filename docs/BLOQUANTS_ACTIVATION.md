# Bloquants avant activation LIVE du parcours de souscription (CGV V2.1)

L'interrupteur `app_config/merchant_contracts.enabled` reste à `false` en
production tant qu'un seul point de cette liste n'est pas levé. La tranche 1
(demande, vérification manuelle, alertes, confirmation, origine) ne doit
jamais être activée seule : un contrat confirmé n'aurait ni invitation à
payer, ni rétractation.

## Bloquants

1. **Tranche 2 complète et testée** : rétractation (art. 7, fonction « Me
   rétracter » de l'espace commerçant, accusé de réception), invitation à
   payer et lien de 15 jours (art. 8.1), Checkout par enseigne, webhook
   (activation, paiement tardif remboursé), tâches planifiées (rappel puis
   clôture sans paiement), fins de contrat. Tant qu'elle manque, un contrat
   confirmé reste bloqué à l'état `confirmed`.
2. **Invitation à payer des souscriptions spontanées** : l'art. 8.1 prévoit
   qu'elle est adressée *avec* la confirmation. La tranche 1 envoie la
   confirmation seule (« le premier paiement est demandé par une invitation à
   payer, valable quinze jours ») ; la tranche 2 doit l'envoyer au même moment.
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
8. **Configuration à poser à la main** : aucun outil n'écrit
   `app_config/merchant_contracts` (ni fonction ni page). Les fonctions admin
   de la tranche (commerciaux, liens, codes, vérification, confirmation) sont
   elles aussi coupées tant que l'interrupteur est à `false` : les commerciaux
   et les codes ne peuvent être préparés qu'une fois le parcours ouvert, sauf
   ouverture préalable en mode TEST.
9. **Vérifications non faites sur un service réel** : lecture du PDF dans
   Cloud Storage (remplacée dans les tests), envoi SMTP réel des e-mails de la
   tranche (remplacé dans les tests), tâche planifiée `merchantContractAlerts`
   déclenchée par Cloud Scheduler, requêtes Firestore en production (index
   simples supposés suffisants : `owner_uid` + `state`, `enseigne_id` +
   `state in`, `siret`).
10. **Décisions à confirmer** : jours ouvrés = lundi à vendredi hors les 11
    jours fériés de France métropolitaine (lundi de Pentecôte compris) ; adresse
    des alertes (`admin_alert_email`, par défaut contact@proxiplay.fr) ;
    remise de première année plafonnée pour laisser au moins 1 € HT.
