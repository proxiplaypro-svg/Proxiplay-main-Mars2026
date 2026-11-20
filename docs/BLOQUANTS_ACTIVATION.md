# Bloquants avant activation LIVE du parcours de souscription (CGV V2.1)

**Version minimale (décision du 20 novembre 2026)** : souscription, paiement,
rétractation et webhook automatiques ; tout le reste (rappels, clôture,
désactivation, remboursements, fins de contrat) est suivi à la main par
l'admin, avec un digest quotidien. Plus de sous-tranche 2b-2 (statuts 1.14,
compteur Accompagnée 1.15-min). Le code de la sous-tranche 2b-1 (lots 1.9 et
1.12) reste dans la branche `phase1-t2b` mais **n'est pas déployé**.

L'interrupteur `app_config/merchant_contracts.enabled` met en pause les
**nouvelles ventes** seulement (aperçu et envoi d'une demande). Il reste à
`false` en production tant qu'un seul point de cette liste n'est pas levé.
Les contrats existants restent suivis quel que soit l'interrupteur.

## Déploiement : fonction par fonction

Déployer uniquement avec `firebase deploy --only functions:<nom>,…`. **Jamais
`firebase deploy --only functions` sans liste** : `index.js` exporte aussi les
fonctions de 2b-1, qui seraient déployées.

**À déployer**

| Fonction | Rôle |
|---|---|
| `getMyMerchantContracts` | espace commerçant : contrats, catalogue si ventes ouvertes |
| `previewMerchantContract`, `submitMerchantSubscriptionRequest` | nouvelle demande (seules fonctions bloquées par l'interrupteur) |
| `reportMerchantVisit` | signalement d'une visite (art. 4.2) |
| `adminUpsertSalesRep`, `adminCreateRepLink`, `adminUpsertPromoCode` | commerciaux, liens, codes |
| `adminRecordMerchantContractChecks`, `adminRefuseMerchantContract`, `adminFindSimilarEnseignes`, `adminConfirmMerchantContract` | vérification, refus, confirmation (art. 4.1) |
| `merchantContractAlerts` | tâche planifiée : alertes de délai de vérification (art. 4.1) |
| `adminUpdateMerchantContractsConfig` | configuration |
| `getPaymentInvitation`, `adminSendPaymentInvitation` | page de paiement ; envoi ou renvoi de l'invitation (manuel après la rétractation) |
| `createContractCheckoutSession` | session Checkout au clic |
| `withdrawMerchantContract`, `adminRecordWithdrawal` | rétractation (art. 7) |
| `merchantMailOutbox`, `adminRetryMailOutbox`, `adminAbandonMailOutbox`, `adminResolveAlert` | file de reprise des e-mails, alertes |
| `merchantContractDigest` | tâche planifiée : digest quotidien à 8 h (lecture seule) |
| `stripeWebhook` | fonction existante, modifiée (contrats V2.1) |

Le webhook embarque des modules modifiés par 2b-1 (`merchant_contract_billing.js` :
`refundInvoice`, `suspended_at` remis à `null` après régularisation ;
`merchant_contract_checkout.js` : verrou qui relit l'état ;
`merchant_contract_payment.js` : option de rappel inutilisée sans le lot 1.9).
Ces changements sont couverts par la suite complète.

**À ne pas déployer**

| Fonction | Pourquoi |
|---|---|
| `merchantContractSchedule` | lot 1.9 (tâches automatiques) remplacé par le digest et le suivi manuel |
| `disableMerchantRenewal` | lot 1.12 : désactivation faite à la main dans Stripe |
| `adminRefundRenewal`, `adminEndContract` | lot 1.12 : remboursements et fins de contrat faits à la main dans Stripe |

Sur le site et la console, ne pas livrer les commits qui appellent ces
fonctions : site `2e3bf36` (bouton « Désactiver le renouvellement ») ; console
`4314158` (formulaires de fin de contrat et de remboursement art. 9). Le
commit site `f8f7543` (lignes « suspendu » et « clos sans paiement ») est
sans effet sans le lot 1.9. Les correctifs `phase1 t2b fix` (site et
canonique) et le digest sont, eux, à livrer.

## Bloquants

1. **Tranches 1 et 2a complètes et testées** (branches `phase1-t1`,
   `phase1-t2a`), plus le correctif d'interrupteur et le digest (branche
   `phase1-t2b`). Rien d'autre à développer pour la version minimale.
2. **Essais Stripe réels (mode TEST)** : ceux de la sous-tranche 2a ont été
   lancés par le propriétaire le 20 novembre 2026 et sont conformes (course,
   facture ouverte, avoir, session Checkout). Restent les événements réels du
   webhook au format 2026-10-28.endive. Le script `essais-2b.cjs` n'est plus
   nécessaire (lot 1.12 non déployé).
3. **CGV adaptées au suivi manuel** : le texte V2.1 promet des actions que le
   code ne fait plus automatiquement (rappels, clôture, désactivation en
   ligne, remboursements, relances de grâce, suspension). À adapter avant la
   publication. Les e-mails `activationNotice`, `renewalFailedNotice` et
   `paymentInvitation` sont alignés sur le suivi manuel (facture par e-mail ;
   désactivation et changement de moyen de paiement par demande à
   contact@proxiplay.fr, au moins 7 jours avant l'échéance pour la
   désactivation). **Aucun code n'envoie la facture** : activer l'envoi des
   factures par Stripe, ou l'envoyer à la main. La phrase de l'invitation
   « peut être close après un rappel » est inchangée, à confronter au texte
   final des CGV.
4. **PDF daté des CGV** : publié le jour effectif de la mise en production,
   archivé, déposé dans Cloud Storage (bucket par défaut) au chemin
   `cgv.storage_path`, avec `version`, `sha256` et `url` dans
   `app_config/merchant_contracts.cgv`. Sans lui, aucune demande n'est
   acceptée et aucune confirmation ne part (`cgv_not_configured`,
   `cgv_pdf_mismatch`). Le lien « Conditions générales de vente » du site
   pointe aujourd'hui vers un PDF absent.
5. **Suppression d'une enseigne liée à une demande ou à un contrat** : la règle
   Firestore actuelle permet au propriétaire de supprimer son enseigne depuis
   l'app (`enseignes` : `allow delete` si `ownsShopData`). La confirmation
   vérifie que l'enseigne existe et appartient au demandeur ; une suppression
   après confirmation laisse un contrat sans enseigne. À traiter avant
   l'ouverture (règle, suppression côté serveur ou release de l'app).
6. **Vérifications Stripe** (lot 0.11) : relances sur 3 semaines, action
   finale « marquer impayé », ne pas annuler les paiements à confirmer, lien
   d'authentification bancaire, pied de facture ; endpoint TEST à la version
   d'API de LIVE.
7. **Portail client Stripe et factures** : le portail et la liste des
   factures de l'espace commerçant (`merchant_billing_portal.js`) utilisent le
   client Stripe V1 (`merchant_subscriptions/{uid}`), jamais le client de
   l'enseigne d'un contrat V2.1. Pour un contrat V2.1, le commerçant n'a donc
   ni ses factures, ni le changement de moyen de paiement, ni la
   désactivation dans son espace. Garder l'annulation coupée dans le portail
   (décision 7) ; toute désactivation passe par l'admin.
8. **Codes promotionnels** : la tranche 1 tient le miroir Firestore
   `promo_codes` ; la création du code Stripe correspondant (Firestore vers
   Stripe, par une fonction serveur) n'est pas faite. Aucun code ne doit être
   créé ou modifié à la main dans Stripe.
9. **Règles Firestore déployées** : les règles des nouvelles collections sont
   dans `firebase/firestore.rules` du dépôt canonique (y compris
   `renewal_reminders` et `schedule_alerts`, inutilisées sans le lot 1.9,
   sans risque : lecture admin seule). La console admin a son propre
   `firestore.rules`, non modifié. Il faut établir lequel est déployé
   (lot 0.2) avant tout déploiement.
10. **Configuration** : l'outil admin `adminUpdateMerchantContractsConfig`
    (console, page Souscriptions) écrit `app_config/merchant_contracts` avec
    validation, contrôle du PDF et journal. Reste à poser la configuration
    réelle le jour de l'ouverture.
11. **Vérifications non faites sur un service réel** : lecture du PDF dans
    Cloud Storage, envoi SMTP réel, tâches planifiées `merchantContractAlerts`,
    `merchantMailOutbox` et `merchantContractDigest` déclenchées par Cloud
    Scheduler (1re génération), requêtes Firestore en production (index
    simples supposés suffisants : `owner_uid`, `state`, `status`, `resolved`).
12. **Adresse des alertes et du digest** : à fournir par le propriétaire, puis
    à poser avec l'outil de configuration (`admin_alert_email`) ; à défaut,
    tout part à contact@proxiplay.fr.
13. **Avoirs** : option `credit_notes_enabled`, désactivée par défaut, à
    activer après validation du comptable.
14. **Secret Stripe** : `reportMerchantVisit`, `withdrawMerchantContract` et
    `adminRecordWithdrawal` déclarent `STRIPE_SECRET_KEY` (expiration de
    session, remboursement) : à vérifier au déploiement.
15. **E-mail Stripe d'authentification bancaire** : à activer dans le
    Dashboard (décision 8) ; ProxiPlay n'envoie rien pour ce cas.
16. **Digest et SMTP** : le digest n'écrit rien. Un échec d'envoi est
    journalisé (Cloud Logging) et la tâche est rejouée jusqu'à 3 fois par Cloud
    Scheduler ; il n'entre pas dans la file de reprise et ne crée pas
    d'alerte. Comme le digest est recalculé chaque jour, le lendemain reprend
    tout.
17. **Accès payant non relié au contrat V2.1** : le contrôle de publication
    (`merchant_publication_access.js`) lit `merchant_subscriptions/{uid}` (V1)
    et non `enseigne_subscriptions`. L'activation, la grâce et la suspension
    d'un contrat V2.1 n'ouvrent ni ne ferment donc aucune fonction de l'app ;
    toute suspension (art. 11, 18) est manuelle.

## Suivi manuel (sans code)

| Action | Où | Signalé par |
|---|---|---|
| Invitation à payer après la rétractation (démarchage) | console, « Envoyer l'invitation » | digest |
| Rappel avant la fin du lien de 15 jours | console, « Renvoyer l'invitation » (nouveau lien, même date de fin) | digest (3 jours avant) |
| Clôture d'une souscription non payée | aucun outil : le contrat reste « invité », lien expiré, rien n'est facturé ; le renvoi garde la date de fin dépassée, donc aucun nouveau lien possible | digest |
| Rappel J-45 (art. 9) | e-mail manuel | digest (date limite) |
| Désactivation du renouvellement | Stripe : annuler à la fin de la période ; pendant la grâce : annuler la facture puis l'abonnement | demande du commerçant |
| Remboursement art. 9, 10, 23 | Stripe : remboursement puis annulation | demande, décision admin |
| Relances de grâce, mise en demeure, résiliation (art. 11, 18) | e-mails manuels ; Stripe : annulation | digest |

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
- Version minimale avec suivi manuel ; 2b-2 abandonnée ; 2b-1 non déployée.
- Interrupteur : pause des nouvelles ventes seulement ; rétractation,
  webhook, fonctions admin (confirmation comprise) et paiement d'un contrat
  déjà invité fonctionnent toujours.
- Digest quotidien en lecture seule à l'adresse des alertes.
