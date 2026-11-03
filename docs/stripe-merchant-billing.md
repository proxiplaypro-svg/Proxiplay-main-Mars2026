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

- mode Stripe imposé par le projet Firebase (`stripe_mode.js`) : **LIVE
  uniquement** sur `proxi-play-odzp2e`, **TEST uniquement** sur un projet
  `demo-…` (émulateurs). En production, une clé `sk_test_…`/`rk_test_…` est
  refusée, un événement ou un abonnement TEST n'écrit rien (événement tracé
  `ignored_livemode_mismatch`) et un miroir TEST n'ouvre aucun droit (serveur
  et `firestore.rules`) ;
- une clé `sk_live_…` est **refusée** tant que `STRIPE_LIVE_MODE_ENABLED`
  ne vaut pas `true` ; sans ce drapeau les paiements sont **fermés** en
  production (aucun Checkout, page « paiement pas encore ouvert ») ;
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

Les clés de **TEST** (`sk_test_…`) servent uniquement en local, avec les
émulateurs (§11 sexies) : elles sont **refusées** sur `proxi-play-odzp2e`.

Sur la production, tant que les paiements restent fermés, aucun secret
n'est nécessaire pour l'espace commerçant (§8 bis). Seul le déploiement
anticipé des fonctions Stripe l'exigerait ; une valeur qui n'est pas une
clé Stripe le laisse alors inutilisable :

```
firebase functions:secrets:set STRIPE_SECRET_KEY --project proxi-play-odzp2e      # saisir : desactive
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project proxi-play-odzp2e  # saisir : desactive
```

La clé `sk_live_…` ne sera posée qu'au passage LIVE (§9). Collez toute clé
**uniquement** à l'invite du terminal. Aucune clé publique `pk_…` n'est
nécessaire (Checkout et portail sont hébergés par Stripe).

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

1. En local uniquement (émulateurs, projet `demo-…`, §11 sexies) : le
   projet de production refuse toute clé et tout événement TEST.
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

## 8 bis. Premier déploiement, paiements fermés

But : l'espace commerçant du site affiche le compte, les enseignes et les
offres, avec « Le paiement en ligne ouvrira prochainement » et le bouton
« Souscrire » désactivé. Aucune règle Firestore, aucune fonction existante
n'est modifiée.

Paiements fermés, le site n'appelle que `getMerchantBillingAccount` :
`listMerchantInvoices` et le portail ne sont appelés que pour un compte qui a
un Customer Stripe, le Checkout que si `paymentsEnabled` est vrai.
`getMerchantBillingAccount` ne déclare **aucun secret** : le CLI ne valide
les secrets que des fonctions ciblées par `--only`, il n'en faut donc aucun.

1. Branche à jour (runtime Node 22) et tests verts (§12).
2. Lecture seule, compte propriétaire du projet :
   ```
   firebase functions:list --project proxi-play-odzp2e
   ```
   `getMerchantBillingAccount` doit être absente (sinon s'arrêter : ce n'est
   plus une création). Puis, depuis `firebase/functions` :
   `node scripts/check_stripe_config.js` doit afficher « paiements fermés ».
   `.env.proxi-play-odzp2e` ne doit contenir ni `STRIPE_LIVE_MODE_ENABLED`
   ni `STRIPE_TAX_MODE`.
3. Contrôle à blanc, puis déploiement de cette seule fonction :
   ```
   firebase deploy --only functions:getMerchantBillingAccount --project proxi-play-odzp2e --dry-run
   firebase deploy --only functions:getMerchantBillingAccount --project proxi-play-odzp2e
   ```
   Jamais `firebase deploy` sans `--only` (règles et toutes les fonctions).
4. Vérifier : `functions:list` montre `getMerchantBillingAccount`,
   us-central1, nodejs22 ; sur le site, un commerçant connecté voit son
   espace sans paiement possible.
5. Retour arrière (fonction nouvelle) :
   ```
   firebase functions:delete getMerchantBillingAccount --region us-central1 --project proxi-play-odzp2e
   ```

Les trois autres fonctions (`listMerchantInvoices`,
`createMerchantCheckoutSession`, `createMerchantBillingPortalSession`)
déclarent `STRIPE_SECRET_KEY` : leur déploiement échoue tant que ce secret
n'a pas de version active (« Failed to validate secret versions »). Les
déployer à l'ouverture des paiements, avec la clé LIVE (§9). Les déployer
plus tôt impose un secret temporaire non Stripe (ex. `desactive`), refusé à
chaque appel (`payments_closed`).

## 8 ter. Tarif préférentiel (ex. 300 € HT la 1re année, puis 365 € HT/an)

Tout se fait dans le tableau de bord Stripe (mode du projet : LIVE en
production), sans interface Admin. La validation du compte reste dans l'app.

1. **Une seule fois** — *Product catalog* → *Coupons* → *Create coupon* :
   montant fixe **65,00 EUR**, durée **Once** (« une seule fois » : seule la
   première facture annuelle est réduite, le renouvellement repart à 365 €),
   *Apply to specific products* → produit **Autonome**.
2. **Pour chaque commerçant** — dans ce coupon, *Add promotion code* :
   - code personnel, ex. `MALLE300` (lettres, chiffres, `-`, `_`) ;
   - *Limit to one redemption* (1 utilisation) et, si souhaité, une date
     d'expiration ;
   - **métadonnée obligatoire** `merchantUserId` = UID Firebase du compte
     commerçant (Firebase Console → Authentication, recherche par e-mail).
3. Envoyer au commerçant le lien
   `https://www.proxiplay.fr/espace-commercant/?offre=MALLE300`.

Le commerçant se connecte avec son compte ProxiPlay, clique « Souscrire » :
le serveur vérifie le code chez Stripe (actif, mode attendu, réservé à cet
UID, 1re facture seulement, bon produit, non utilisé, non expiré) puis crée
le Checkout pour **son compte authentifié** avec la remise. Le paiement est
rattaché par l'UID (métadonnées de l'abonnement), jamais par l'e-mail ; un
code d'un autre compte est refusé.

**Code de campagne partagé** (ex. `FRIENDS20`, prospection) : même coupon,
mais un code commun à tous les prospects. Dans Stripe, sur le code :
métadonnée `proxiplay_usage` = `campagne` (au lieu de `merchantUserId`) et
option *First-time order only* cochée. Lien :
`https://www.proxiplay.fr/espace-commercant/?offre=FRIENDS20`. Le serveur
le réserve à un **premier abonnement** du compte (aucun abonnement Stripe
antérieur) ; le paiement reste rattaché au compte connecté. Un code sans
`merchantUserId` ni `proxiplay_usage=campagne` est refusé.

À ne pas utiliser : un « Payment Link » Stripe envoyé directement. Le
paiement y est anonyme ; le webhook ne le rattache à aucun compte
(`ignored_unknown_merchant`) et n'ouvre aucun droit.

## 9. Passage TEST → LIVE (plus tard, sur décision)

1. Recréer les 2 prix (et le taux de TVA éventuel) en mode LIVE.
2. Remplacer `STRIPE_PRICE_*`, `STRIPE_TAX_RATE_ID`, `STRIPE_SECRET_KEY`
   (`sk_live_…`) et recréer le webhook LIVE (`whsec_…` LIVE).
3. Poser `STRIPE_LIVE_MODE_ENABLED=true` — **sans cela la clé LIVE est
   refusée**.
4. Un ancien miroir TEST (`stripe_livemode: false`) éventuellement présent
   en production n'ouvre aucun droit, ne bloque pas la souscription LIVE et
   son Customer TEST n'est jamais réutilisé : il est remplacé au premier
   Checkout ou webhook LIVE. `manual_access` et `legacy_access` sont
   conservés.

## 10. Droits commerçants (décisions du 03/11/2026)

| Action | Règle |
|---|---|
| Inscription, connexion, fiche commerçant, espace commerçant, consultation des offres | **Gratuit** |
| Créer, publier ou relancer un jeu | Exige un droit de publication (ci-dessous) |
| Lire, masquer, supprimer ses jeux existants ; jeux déjà en cours | **Jamais bloqué** |
| Souscrire (Stripe Checkout) | Compte **validé** (`account_status == approved`) — refusé côté serveur sinon |

Statuts explicites (`computePublicationAccess`, miroir exact dans
`firestore.rules` → `hasMerchantPublicationAccess`) :

| Statut | Publication | Origine |
|---|---|---|
| `active` | oui | abonnement Stripe actif (y compris résiliation programmée : effet à la fin de la période payée) |
| `legacy` | oui | droit commercial existant, posé par le script de transition, jamais retiré automatiquement |
| `manual` | oui | activation manuelle Admin (`manual_access`, éventuellement datée) |
| `grace` | oui | renouvellement impayé, **14 jours** depuis l'échéance impayée (`MERCHANT_BILLING_GRACE_DAYS`) |
| `suspended` | non | délai de grâce dépassé — jeux, comptes, historiques conservés |
| `ended` | non | abonnement terminé |
| `pending_payment` | non | premier paiement non abouti |
| `free` | non | aucun abonnement |

Contrôles appliqués **côté Firebase** :

1. `firestore.rules` → création d'un document `games` par un commerçant ;
2. `generateInstantWinnersForGame` → publication (`publishOnSuccess`) d'un
   jeu non encore public. Un jeu déjà public (retry, jeu en cours) et les
   appels admin ne sont jamais bloqués.

Régularisation : dès que Stripe confirme le paiement (`invoice.paid`), le
webhook remet le statut à `active` et efface `grace_until` : les droits
reviennent automatiquement. L'espace commerçant affiche la date de fin de
grâce et un lien vers la facture Stripe en attente.

## 11. Transition non destructive (à faire dans cet ordre)

Le contrôle est **inactif** tant que
`app_config/merchant_billing.enforce_publication_access` ne vaut pas `true` :
déployer ce code ne change rien pour personne.

```
cd firebase/functions
node scripts/merchant_publication_access.js backfill-legacy            # simulation
node scripts/merchant_publication_access.js backfill-legacy --apply --confirm=proxi-play-odzp2e
node scripts/merchant_publication_access.js report                     # lecture seule
node scripts/merchant_publication_access.js enforce on --apply --confirm=proxi-play-odzp2e
```

- `backfill-legacy` ajoute seulement `legacy_access` (merge) aux commerçants
  **validés** (rôle commerçant ou propriétaire d'enseigne). Il ne touche ni
  abonnement, ni tarif négocié, ni activation manuelle, ni jeu.
  `--include-pending` ajoute les comptes en attente (décision à prendre).
- `enforce on` est **refusé** tant qu'un commerçant validé propriétaire
  d'une enseigne n'aurait aucun droit (sauf `--force`).
- `enforce off --apply` revient instantanément à la situation actuelle.
- `report` liste les commerçants sans droit qui ont encore des jeux en
  cours : **aucun jeu n'est arrêté**, ces cas sont à arbitrer.

## 11 bis. Résiliation

Portail Stripe (§6) : n'autoriser que l'annulation **à la fin de la période**
(`cancel_at_period_end`). Le statut reste `active` jusqu'à l'échéance, puis
`ended`. Ne pas activer l'annulation immédiate.

## 11 ter. Points ouverts

- **Régime de TVA** (§3) — bloquant pour ouvrir le paiement.
- **Ne pas fusionner** `feat/stripe-merchant-billing` en production avant
  validation de la TVA et recette complète.
- **Message dans l'app** : un commerçant sans droit qui crée un jeu dans
  l'app Flutter voit aujourd'hui l'erreur générique de création ; Flutter
  n'a pas été modifié. Un message dédié (« abonnement requis », lien vers
  l'espace commerçant) est recommandé avant `enforce on`.
- **Jeux en cours d'un commerçant suspendu** : conservés et non interrompus ;
  liste fournie par `report` pour décision.
- **Comptes en attente au moment de la transition** : droit existant ou non
  (`--include-pending`) ?
- **Second abonnement détecté** : remboursement et résiliation manuels.
- **Échec préexistant** (antérieur à ce chantier) :
  `game_lifecycle_instant.test.js` › « completing a partial calendar on an
  already-started game is allowed for an admin repair ».

## 11 quater. Message dans l'application

Lorsqu'un commerçant sans droit tente de créer ou publier un jeu, l'app
affiche : « Un abonnement ProxiPlay actif est nécessaire pour publier un jeu.
Rendez-vous sur www.proxiplay.fr/espace-commercant/ pour découvrir les
offres. » — **uniquement** si le contrôle est activé et l'accès refusé
(Callable `getMerchantPublicationAccess`, refus serveur
`subscription_required`, ou refus des règles confirmé par cette Callable).
Si la vérification échoue (réseau, fonction non déployée), le comportement
actuel est conservé. Fichiers : `lib/utils/merchant_publication_access.dart`,
`add_game_commercant_page_widget.dart`.

## 11 quinquies. Prix configurés (mode test, 03/11/2026)

`firebase/functions/.env.proxi-play-odzp2e` (ignoré par Git, lu au
déploiement) et `.env.local` (émulateurs) :

```
STRIPE_PRICE_AUTONOME=price_1UXUSsJIcR5ze9rtbYnhXaM0
STRIPE_PRICE_ACCOMPAGNEE=price_1UXUUWJIcR5ze9rtDR018hUF
```

Vérification (aucune écriture) :
`node scripts/check_stripe_config.js`, et avec une clé de test dans le
terminal pour contrôler montant/devise/périodicité chez Stripe.

## 11 sexies. Premier paiement de test en local (sans déploiement)

1. `firebase emulators:start --only auth,firestore --project demo-proxiplay-stripe`
2. `node firebase/functions/scripts/seed_merchant_billing_emulator.js`
3. `stripe listen --forward-to http://127.0.0.1:35001/stripeWebhook` → noter le `whsec_…`
4. Terminal (PowerShell) :
   `$env:STRIPE_SECRET_KEY="sk_test_…"; $env:STRIPE_WEBHOOK_SECRET="whsec_…"; $env:STRIPE_TAX_MODE="none"`
   puis `node firebase/functions/scripts/local_billing_server.js`
5. Servir le site (`proxiplay-website`) sur `http://localhost:5500` et ouvrir
   `/espace-commercant/?emulator=1&functionsPort=35001`
6. Se connecter avec le compte commerçant de test, Souscrire, carte `4242 4242 4242 4242`.

## 12. Tests locaux

```
# Functions (émulateurs Firestore + Auth, aucun appel Stripe réel)
firebase emulators:exec --only firestore,auth --project demo-proxiplay-stripe \
  "cd firebase/functions && node --test --test-concurrency=1 test/merchant_checkout.test.js test/merchant_publication_access.test.js test/stripe_webhook.test.js test/stripe_discovery_without_config.test.js test/merchant_referral_engine.test.js test/merchant_signup_referral.test.js test/firestore_rules_merchant_billing.test.js test/stripe_mode_security.test.js"

# Comptes de test pour l'espace commerçant (émulateurs uniquement)
node firebase/functions/scripts/seed_merchant_billing_emulator.js
```
