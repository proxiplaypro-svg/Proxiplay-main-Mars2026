# Paiement commerçant Stripe + parrainage commerçant 100 € — guide Pascal

Ce document liste **uniquement** ce que Pascal doit faire manuellement. Rien
dans le code n'invente de clé Stripe ; rien ne doit jamais être collé en
clair dans Git.

## 1. Compte Stripe (mode TEST d'abord)

**Où aller** → https://dashboard.stripe.com → créer un compte (ou utiliser
le compte existant) → rester en mode **TEST** (bouton en haut à droite du
Dashboard) tant que ce chantier n'est pas validé en production.

**Quoi créer** → rien à cette étape, juste confirmer l'accès au Dashboard.

## 2. Produits et prix (3 offres)

**Où aller** → Dashboard Stripe → *Product catalog* → *Add product*.

**Quoi créer**, une fois par offre, en mode **récurrent annuel** :

| Offre | Prix HT/an (France métropolitaine) |
|---|---|
| Proximité | 365,00 € |
| Secteurs spécifiques | 1 095,00 € |
| Grandes enseignes (à partir de) | 1 825,00 € |

Pour chaque produit : *Pricing* → *Recurring* → *Yearly* → montant exact ci-
dessus → laisser la TVA à Stripe gérer via un Tax Rate (étape suivante), ou
configurer Stripe Tax si vous préférez — à votre choix, mais voir §3.

**Quelle valeur récupérer** → l'ID de prix commence par `price_...` (pas
l'ID produit `prod_...`). Il y en a 3, un par offre.

**Où le placer** → ce ne sont pas des secrets (ils sont visibles dans vos
URLs Stripe Dashboard et ne donnent aucun droit), mais ils n'existent pas
dans le code : à configurer comme *paramètres d'environnement non secrets*
des Cloud Functions (`firebase functions:config:set` n'existe plus en
Gen2/params ; avec `firebase-functions/params`, définissez-les comme
variables d'environnement au déploiement, par exemple dans un fichier
`.env.proxi-play-odzp2e` à la racine de `firebase/functions/` — **ce fichier
ne doit jamais être commité** s'il contient un jour une vraie valeur de
production sensible, bien que ces ID ne le soient pas strictement) :

```
STRIPE_PRICE_PROXIMITE=price_...
STRIPE_PRICE_SECTEURS_SPECIFIQUES=price_...
STRIPE_PRICE_GRANDES_ENSEIGNES=price_...
```

## 3. Taux de TVA (20 %)

**Où aller** → Dashboard Stripe → *Product catalog* → *Tax rates* → *New
tax rate*.

**Quoi créer** → un taux "TVA France" à **20 %**, type *Exclusive* (ajouté
au prix HT, jamais inclus dedans).

**Quelle valeur récupérer** → l'ID commence par `txr_...`.

**Où le placer** → même mécanisme que les prix ci-dessus :

```
STRIPE_TAX_RATE_TVA_20=txr_...
```

## 4. Clés API

**Où aller** → Dashboard Stripe → *Developers* → *API keys*.

**Quoi récupérer** → la **clé secrète** (`sk_test_...` en TEST, `sk_live_...`
en LIVE plus tard). **Ne jamais** récupérer/utiliser la clé publique
(`pk_...`) côté serveur — elle n'est pas utilisée dans cette architecture,
Stripe Checkout étant hébergé par Stripe, pas intégré en JS côté client.

**Où la placer** → Secret Manager Firebase (même mécanisme que
`GOOGLE_PLACES_API_KEY`, déjà en place sur ce projet) :

```
firebase functions:secrets:set STRIPE_SECRET_KEY --project proxi-play-odzp2e
```

Collez la clé **uniquement** quand la commande vous le demande dans le
terminal — jamais dans un fichier, un message, ou Git.

## 5. Webhook

**Où aller** → Dashboard Stripe → *Developers* → *Webhooks* → *Add
endpoint*.

**Quelle URL** → une fois les Cloud Functions déployées, l'URL est :
`https://us-central1-proxi-play-odzp2e.cloudfunctions.net/stripeWebhook`

**Quels événements écouter** (cocher exactement ceux-ci, pas plus) :
`invoice.paid`, `invoice.payment_failed`, `customer.subscription.updated`,
`customer.subscription.deleted`, `charge.refunded`, `charge.dispute.created`.

**Quelle valeur récupérer** → le *Signing secret* de cet endpoint,
`whsec_...` (visible après création de l'endpoint, bouton *Reveal*).

**Où la placer** → Secret Manager, comme la clé secrète :

```
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project proxi-play-odzp2e
```

## 6. Stripe Customer Portal

**Où aller** → Dashboard Stripe → *Settings* → *Billing* → *Customer
portal*.

**Quoi configurer** → activer le portail, autoriser au minimum : voir la
facturation, changer le moyen de paiement, annuler l'abonnement à la fin de
la période en cours (pas d'annulation immédiate si vous souhaitez garantir
la période déjà payée). Pas d'action de notre côté au-delà de cette
configuration : le code crée uniquement la session, jamais la config du
portail.

## 7. Informations société / TVA / coordonnées bancaires

**Où aller** → Dashboard Stripe → *Settings* → *Business settings* (raison
sociale, SIRET/SIREN, adresse) puis *Settings* → *Bank accounts and
scheduling* (IBAN de réception des paiements Stripe → ProxiPlay).

**Important** → ce chantier a choisi (décision explicite de Pascal, validée
en amont de l'implémentation) : TVA à 20 % ajoutée au prix HT référencé en
§2. Si votre régime de TVA réel diffère de cette hypothèse (franchise en
base, auto-liquidation...), signalez-le avant la bascule en LIVE : le taux
`STRIPE_TAX_RATE_TVA_20` (§3) est le seul endroit à changer, rien à modifier
dans le code.

## 8. Passage TEST → LIVE

Une fois la recette validée en Stripe TEST (voir rapport final, section
TESTS) :

1. Recréer les mêmes produits/prix/taux de TVA en mode **LIVE** (Stripe ne
   duplique pas automatiquement du TEST vers le LIVE).
2. Récupérer les nouveaux ID (`price_...`, `txr_...`) et la clé secrète
   `sk_live_...` → remplacer les valeurs des §2/§4 par les valeurs LIVE
   (mêmes noms de secrets/paramètres, nouvelles valeurs).
3. Recréer l'endpoint webhook (§5) en pointant sur le même URL mais en mode
   LIVE, récupérer le nouveau `whsec_...` LIVE.
4. Vérifier qu'aucun test automatisé ne tourne plus jamais avec une clé
   LIVE (déjà garanti par ce chantier : les tests ne lisent aucun secret
   réel, voir rapport final).

## 9. Commerçants déjà existants

Aucune action requise : les enseignes déjà actives aujourd'hui n'ont pas de
document `merchant_subscriptions`, donc aucune régression de statut n'est
introduite par ce chantier. Elles ne deviennent "impayées" à aucun moment —
ce système ne s'applique qu'aux nouvelles souscriptions volontaires.

## 10. Validation des nouvelles inscriptions commerçant via le site

Le site crée un compte avec le même statut `pendingValidation` que
l'inscription commerçant existante dans l'app mobile. La validation
(passage à `approved`) se fait aujourd'hui via l'écran mobile existant
(`validation_commercants_admin_page`) — aucun nouvel écran n'a été ajouté
dans l'admin web pour cette étape spécifique, afin de ne pas dupliquer un
mécanisme qui fonctionne déjà. Si vous préférez valider depuis l'admin web
plutôt que depuis l'app, dites-le : c'est un ajout ciblé et simple à faire
dans un chantier séparé.
