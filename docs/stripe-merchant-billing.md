# Paiement commerçant Stripe + parrainage commerçant 50 € — guide Pascal

Ce document liste **uniquement** ce que Pascal doit faire manuellement. Rien
dans le code n'invente de clé Stripe ; rien ne doit jamais être collé en
clair dans Git.

**Modèle de facturation : un paiement par compte commerçant**, pas par
enseigne. Un commerçant possédant plusieurs enseignes paie un seul
abonnement annuel qui couvre toutes ses enseignes. Un **tarif négocié** peut
toujours être fixé depuis l'Admin (page *Abonnements commerçants*) : il
remplace alors le catalogue pour ce compte.

**Où se passe le paiement** : sur le site, page
`https://www.proxiplay.fr/espace-commercant/` (dépôt `proxiplay-website`,
branche `feat/espace-commercant`). Le commerçant s'y connecte avec **son
compte Firebase de l'app**. L'Admin reste en lecture seule et n'appelle
jamais Stripe.

## Architecture en bref

| Élément | Où | Rôle |
|---|---|---|
| `getMerchantBillingAccount` | Cloud Function (us-central1) | Vérifie que le compte connecté est un commerçant Firebase (`users/{uid}`, rôle `commercant`, compte ni supprimé ni rejeté ni suspendu), liste ses enseignes, renvoie l'état de l'abonnement. |
| `createMerchantCheckoutSession` | Cloud Function | Crée la session Stripe Checkout (mode abonnement annuel). Prix résolu **côté serveur** uniquement. |
| `stripeWebhook` | Cloud Function HTTP | **Seule** source d'activation des droits payants. Signature vérifiée, idempotent, insensible à l'ordre d'arrivée. |
| `createMerchantBillingPortalSession` | Cloud Function | Ouvre le portail client Stripe (moyen de paiement, factures, résiliation). |
| `listMerchantInvoices` | Cloud Function | Factures du commerçant connecté (liens Stripe, aucune donnée de carte). |
| `adminSetMerchantManualAccess` | Cloud Function (admin) | Activation manuelle hors Stripe ; jamais modifiée par le webhook. |
| `merchant_subscriptions/{uid}` | Firestore | Miroir lu par le site et l'Admin, écrit uniquement par les Functions. |

Garde-fous déjà en place dans le code :

- une clé `sk_live_…` est **refusée** tant que `STRIPE_LIVE_MODE_ENABLED`
  ne vaut pas `true` ;
- aucun Checkout n'est créé tant que la fiscalité (`STRIPE_TAX_MODE`) n'est
  pas explicitement configurée ;
- le prix Stripe configuré est vérifié avant chaque Checkout (montant HT,
  EUR, annuel, actif) ;
- double abonnement bloqué à 4 niveaux (miroir, verrou anti double-clic,
  abonnements ouverts côté Stripe, réutilisation de la session ouverte) ;
  un éventuel second abonnement est signalé
  (`duplicate_subscription_alert`), jamais résilié automatiquement ;
- les URL de retour Stripe sont limitées aux domaines ProxiPlay.

## 1. Compte Stripe — rester en mode TEST

Dashboard Stripe → bouton **Test mode** activé. Tout ce qui suit se fait
d'abord en TEST.

## 2. Produits et prix (2 offres)

Dashboard → *Product catalog* → *Add product*, **récurrent, annuel**, en EUR,
prix **HT** :

| Offre | Prix HT / an | Variable à renseigner |
|---|---|---|
| Autonome | 365,00 € | `STRIPE_PRICE_AUTONOME=price_…` |
| Accompagnée | 1 000,00 € | `STRIPE_PRICE_ACCOMPAGNEE=price_…` |

Le montant doit être **exactement** celui-ci : sinon le serveur refuse le
Checkout (contrôle anti-erreur de collage). Si vous utilisez Stripe Tax
(§3, mode `automatic`), réglez aussi le *Tax behavior* du prix sur
*Exclusive*.

Ces ID ne sont pas secrets : fichier `firebase/functions/.env.proxi-play-odzp2e`
(non commité, déjà ignoré par Git).

## 3. Fiscalité — DÉCISION À VALIDER (bloquant)

Le code ne présume **aucun** régime de TVA. Choisir, après validation
comptable, **une** des trois valeurs :

```
STRIPE_TAX_MODE=tax_rate     # + STRIPE_TAX_RATE_ID=txr_… (taux créé dans Stripe)
STRIPE_TAX_MODE=automatic    # Stripe Tax (à activer et configurer dans Stripe)
STRIPE_TAX_MODE=none         # aucune taxe ajoutée (ex. franchise en base)
```

Sans cette variable, la page affiche « paiement en ligne pas encore ouvert »
et aucun Checkout n'est possible.

## 4. Clé secrète

Dashboard → *Developers* → *API keys* → clé secrète `sk_test_…`.

```
firebase functions:secrets:set STRIPE_SECRET_KEY --project proxi-play-odzp2e
```

Collez la clé **uniquement** à l'invite du terminal. Aucune clé publique
`pk_…` n'est nécessaire (Checkout et portail sont hébergés par Stripe).

## 5. Webhook

Après déploiement des Functions : Dashboard → *Developers* → *Webhooks* →
*Add endpoint* :

- URL : `https://us-central1-proxi-play-odzp2e.cloudfunctions.net/stripeWebhook`
- Événements à cocher :
  `checkout.session.completed`, `checkout.session.expired`,
  `customer.subscription.created`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `customer.subscription.paused`,
  `customer.subscription.resumed`, `invoice.paid`,
  `invoice.payment_failed`, `charge.refunded`, `charge.dispute.created`.

Puis le *Signing secret* `whsec_…` :

```
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project proxi-play-odzp2e
```

## 6. Portail client Stripe

Dashboard → *Settings* → *Billing* → *Customer portal* : activer ;
autoriser l'historique des factures, le changement de moyen de paiement et
l'annulation **à la fin de la période** (garde la période payée). Laisser
**désactivé** le changement d'offre tant que la règle de changement en cours
d'année (prorata) n'est pas décidée.

## 7. Domaines et connexion

- Firebase Console → *Authentication* → *Settings* → *Authorized domains* :
  ajouter `www.proxiplay.fr` et `proxiplay.fr` (requis pour « Continuer avec
  Google » ; la connexion e-mail/mot de passe fonctionne déjà).
- Si la clé API web Firebase est restreinte par référent HTTP (Google Cloud
  → *Credentials*), y ajouter `https://www.proxiplay.fr/*`.
- `MERCHANT_BILLING_ALLOWED_ORIGINS` (facultatif) : liste des origines
  autorisées pour les retours Stripe. Par défaut : `www.proxiplay.fr`,
  `proxiplay.fr` et les domaines Firebase du projet.

## 8. Recette en mode TEST

1. Déployer les Functions sur un environnement de test (pas la production).
2. Se connecter sur `/espace-commercant/` avec un compte commerçant de test.
3. Souscrire avec la carte de test `4242 4242 4242 4242` → statut « Actif »
   après réception du webhook (jamais avant).
4. Carte `4000 0000 0000 0341` → échec de paiement → « Paiement en échec ».
5. Renouvellement : *Test clocks* Stripe (avancer d'un an) → nouvelle date
   de renouvellement.
6. Résiliation depuis le portail → « Renouvellement désactivé » puis
   « Résilié » à l'échéance.
7. `stripe events resend <evt_…>` → aucun double effet.
8. Tenter une seconde souscription → refusée.

## 9. Passage TEST → LIVE (plus tard, sur décision)

1. Recréer les 2 prix (et le taux de TVA éventuel) en mode LIVE.
2. Remplacer `STRIPE_PRICE_*`, `STRIPE_TAX_RATE_ID`, `STRIPE_SECRET_KEY`
   (`sk_live_…`) et recréer le webhook LIVE (`whsec_…` LIVE).
3. Poser `STRIPE_LIVE_MODE_ENABLED=true` — **sans cela la clé LIVE est
   refusée**.

## 10. Commerçants existants

Aucune migration. Les commerçants actuels n'ont pas de document
`merchant_subscriptions` et rien ne restreint encore leurs accès : ils ne
deviennent « impayés » à aucun moment. Une activation manuelle peut être
posée par l'Admin (`adminSetMerchantManualAccess`) ; le webhook ne la
modifie jamais.

## 11. Décisions métier encore ouvertes

- **Régime de TVA** (§3) — bloquant pour ouvrir le paiement.
- **Ce que débloque l'abonnement** : aujourd'hui aucun écran ne restreint
  l'accès selon `stripe_entitlement` / `manual_access`. Définir quelles
  fonctions deviennent payantes avant d'appliquer une restriction.
- **Délai de grâce** après un échec de renouvellement (`past_due`) : accès
  conservé ou suspendu pendant les relances Stripe ?
- **Paiement avant validation** : un commerçant `pendingValidation` peut-il
  souscrire ? (Aujourd'hui : oui ; seuls les comptes rejetés ou suspendus
  sont bloqués.)
- **Second abonnement détecté** : remboursement et résiliation manuels par
  l'équipe (aucune action automatique).

## 12. Tests locaux

```
# Functions (émulateurs Firestore + Auth, aucun appel Stripe réel)
firebase emulators:exec --only firestore,auth --project demo-proxiplay-stripe \
  "cd firebase/functions && node --test --test-concurrency=1 test/merchant_checkout.test.js test/stripe_webhook.test.js test/stripe_discovery_without_config.test.js test/merchant_referral_engine.test.js test/merchant_signup_referral.test.js test/firestore_rules_merchant_billing.test.js"

# Comptes de test pour l'espace commerçant (émulateurs uniquement)
node firebase/functions/scripts/seed_merchant_billing_emulator.js
```
