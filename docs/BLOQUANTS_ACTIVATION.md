# Bloquants avant activation LIVE du parcours de souscription (CGV V2.1)

L'interrupteur `app_config/merchant_contracts.enabled` reste à `false` en
production tant qu'un seul point de cette liste n'est pas levé. La tranche 1
(demande, vérification manuelle, alertes, confirmation, origine) ne doit
jamais être activée seule : un contrat confirmé n'aurait ni invitation à
payer, ni rétractation.

## Bloquants

1. **Tranche 2 complète et testée** : rétractation (art. 7, fonction « Me
   rétracter »), invitation à payer et lien de 15 jours (art. 8.1), Checkout
   par enseigne, webhook (activation, paiement tardif remboursé), tâches
   planifiées, fins de contrat. Tant qu'elle manque, un contrat confirmé reste
   bloqué à l'état `confirmed`.
2. **PDF daté des CGV V2.1** : publié le jour effectif de la mise en
   production, archivé, déposé dans Storage au chemin
   `app_config/merchant_contracts.cgv.storage_path`, avec sa version et son
   empreinte SHA-256 dans `cgv`. Sans lui, aucune demande n'est acceptée et
   aucune confirmation ne part (refus `cgv_not_configured`). Le lien
   « Conditions générales de vente » du site pointe aujourd'hui vers un PDF
   absent.
3. **Suppression d'une enseigne liée à une demande ou à un contrat** : la règle
   Firestore actuelle permet au propriétaire de supprimer son enseigne depuis
   l'app (`enseignes` : `allow delete` si `ownsShopData`). La règle n'est pas
   modifiée dans la tranche 1 (elle concerne l'app mobile). La confirmation
   vérifie que l'enseigne existe ; une suppression après confirmation laisse
   un contrat sans enseigne. À traiter avant l'ouverture (règle, fonction de
   suppression côté serveur ou release de l'app).
4. **Vérifications Stripe** (lot 0.11) : relances sur 3 semaines, action
   finale « marquer impayé », ne pas annuler les paiements à confirmer,
   portail (annulation d'un abonnement impayé, art. 9), lien
   d'authentification bancaire, pied de facture ; endpoint TEST à la version
   d'API de LIVE.
5. **Codes promotionnels** : la tranche 1 tient le miroir Firestore
   `promo_codes` ; la création du code Stripe correspondant (sens unique,
   Firestore vers Stripe, par une fonction serveur) relève de la tranche 2.
   Aucun code ne doit être créé ou modifié à la main dans Stripe.
