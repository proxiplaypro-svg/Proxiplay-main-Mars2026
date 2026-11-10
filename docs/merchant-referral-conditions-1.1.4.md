# Conditions dynamiques du parrainage commerçant (ProxiPlay 1.1.4)

Document du 10/11/2026. Rien n'est déployé, et aucune donnée de production
n'a été modifiée. Le fonctionnement du parrainage, des codes, des récompenses
et de la validation des abonnements ne change pas.

## 1. Audit préalable

| Élément | Constat |
|---|---|
| `merchant_referral_conditions.dart` | Texte figé dans l'app, différent du texte validé le 10/11. |
| `parrainage_commercant_page_widget.dart` | Écoute `app_config/merchant_referral` pour `enabled` et ouvre la fenêtre des conditions. |
| `firestore.rules` | `app_config/merchant_referral` : lecture publique, écriture complète par un administrateur, y compris la suppression. |
| `merchant_referral_engine.js`, `merchant_signup_referral.js`, `merchant_checkout.js` | Ils lisent seulement `enabled`, avec le test `=== false`. |
| Admin web (`MerchantReferralProgramToggle.tsx`) | Écrit `setDoc(..., {enabled}, {merge: true})` depuis le client. |
| Production, lecture seule le 10/11 | Le document contient un seul champ, `enabled: false`. |

**Risque relevé à l'audit, corrigé.** Les trois parties ne lisaient pas
`enabled` de la même façon :

| Valeur de `enabled` | Serveur (avant) | Page de parrainage (avant) | Accueil et inscription | Partout (1.1.4) |
|---|---|---|---|---|
| `false` | fermé | fermé | fermé | fermé |
| `true` | ouvert | ouvert | ouvert | ouvert |
| absent, non booléen ou document supprimé | **ouvert** | **ouvert** | fermé | **fermé** |

Décision du 10/11 : **seul `enabled === true` ouvre le programme**. Cela
concerne la génération du code (`merchant_referral_engine.js`), le
rattachement à l'inscription (`merchant_signup_referral.js`, deux
contrôles), le rattachement au paiement (`merchant_checkout.js`) et la page
de parrainage de l'app. En production, la valeur est `enabled: false`, donc
rien ne change aujourd'hui. Les dossiers existants restent traités par
l'Admin (confirmation, approbation, remise), quel que soit l'état du
programme.

## 2. Structure Firestore retenue

```
app_config/merchant_referral
  enabled: bool                      (inchangé, seul champ écrit par l'Admin web)
  conditions: {                      (version en vigueur, lue par l'app)
    version: int                     1, 2, 3…
    format: "plain_v1"
    title: string
    text: string                     paragraphes séparés par une ligne vide,
                                     lignes « - » = liste
    effective_at: timestamp          entrée en vigueur
    updated_at: timestamp            dernière modification
  }

app_config/merchant_referral/conditions_versions/{version}   (historique)
  version, format, title, text, effective_at, updated_at
  published_by: "users/<uid>"
  reason: string                     motif de la publication
  previous_version: int | null
```

- **Historique.** Chaque version est créée avec `create()` et n'est jamais
  réécrite.
- **Version applicable à un parrainage.** C'est la dernière version entrée
  en vigueur avant l'enregistrement du parrainage : `linked_at`, ou à défaut
  `created_at`. La fonction `conditionsVersionAt` la calcule. Un parrainage
  antérieur à la version 1 n'a pas de version (`null`) : il reste soumis aux
  conditions en vigueur à son enregistrement.
- **Dates fiables.** Les deux côtés de la comparaison sont des horodatages
  du serveur Firestore (`serverTimestamp()`) :
  - `linked_at` et `created_at` des parrainages, écrits à l'inscription et
    au paiement ;
  - `effective_at` des versions.

  Aucun client ne peut les écrire : les règles indiquent `write: if false`
  pour `merchant_referrals` et pour l'historique, et `conditions` n'est
  écrit que par la callable.
- **Format texte simple.** Pas de HTML ni de Markdown. Le même découpage
  existe côté serveur (`parseConditionsText`) et côté app
  (`parseMerchantReferralConditionsText`), ce qui permet un aperçu fidèle
  dans l'Admin.

## 3. Sécurité

| Action | Qui |
|---|---|
| Lire `app_config/merchant_referral` | Tout le monde, comme aujourd'hui (l'inscription lit `enabled` avant connexion) |
| Lire `conditions_versions` | Les utilisateurs connectés |
| Écrire `enabled` | Un administrateur depuis un client. Le champ doit rester booléen et c'est le seul qui puisse changer. |
| Écrire `conditions` ou l'historique | Aucun client, même administrateur. Seulement la callable. |
| Supprimer le document | Personne |
| Publier | La callable `adminPublishMerchantReferralConditions`, réservée aux administrateurs (`isTrustedAdmin`) |

**Garanties de la publication :**

- elle valide le texte : 100 à 8 000 caractères, sans balises ni
  caractères de contrôle, 40 blocs au plus, 600 caractères au plus par
  paragraphe ou élément de liste ;
- le titre tient sur une ligne ;
- le motif est obligatoire, de 5 à 200 caractères ;
- le contrôle de version attendue (`expectedVersion`) empêche deux
  administrateurs de s'écraser ;
- l'écriture se fait dans une transaction : création de l'historique, puis
  mise à jour du seul champ `conditions` ;
- elle n'écrit jamais `enabled`, et elle est refusée si `enabled` n'est
  pas déjà un booléen. Elle ne peut donc ni créer le document, ni ouvrir ou
  fermer le programme.

## 4. Application

- La fenêtre « Voir les conditions du programme » relit la configuration à
  chaque ouverture, puis affiche le titre, la ligne « Version N · en
  vigueur depuis le … », les paragraphes et les listes à puces.
- Un indicateur de chargement s'affiche pendant la lecture, limitée à 8
  secondes.
- La source est toujours explicite :

| Source | Affichage |
|---|---|
| Serveur | Conditions seules |
| Cache de l'appareil (hors connexion) | Encadré « Connexion impossible : voici la dernière version enregistrée sur cet appareil. Elle a pu être modifiée depuis. » et bouton « Réessayer » |
| Copie intégrée : document absent, conditions non publiées ou invalides, ni réseau ni cache | Encadré « Les conditions en ligne n'ont pas pu être chargées. Voici la version intégrée à l'application, qui peut ne pas être la plus récente. » et bouton « Réessayer » |

- La copie intégrée est le texte validé le 10/11. Un test vérifie qu'elle
  est identique au fichier serveur `merchant_referral_conditions_v1.txt`.
- L'affichage des conditions ne dépend pas de `enabled`, et l'app n'écrit
  rien.

**Compatibilité.** Les versions 1.1.3 et antérieures gardent leur texte figé
et ne lisent pas `conditions`. L'ajout du champ ne change rien pour elles,
et l'interrupteur de l'Admin web continue de fonctionner.

## 5. Contrat pour le futur écran Admin

1. **Consulter.** Lire `app_config/merchant_referral.conditions`, autorisé
   pour un administrateur.
2. **Modifier et prévisualiser.** Une zone de texte, puis l'appel
   `adminPublishMerchantReferralConditions({title, text, reason, expectedVersion, dryRun: true})`.
   La réponse est `{status: "preview", version, title, blocks}`, avec les
   mêmes blocs que l'app. Aucune écriture.
3. **Publier.** Le même appel avec `dryRun: false`. La réponse est
   `{status: "published", version}`.

   | Erreur | Cause |
   |---|---|
   | `invalid-argument` | Liste des erreurs de validation (dans `details.errors`) |
   | `aborted` | Version modifiée entre-temps, à recharger |
   | `failed-precondition` | `enabled` absent |

4. **Historique.** Lire `conditions_versions`, triée par `version`.

## 6. Migration nécessaire

Aucune modification de données existantes. Il faut seulement **publier la
version 1** après le déploiement de la fonction et des règles, sinon l'app
1.1.4 affichera la copie intégrée avec son avertissement.

```
# Aperçu, sans écriture
node scripts/publish_merchant_referral_conditions.js --project=proxi-play-odzp2e

# Publication
node scripts/publish_merchant_referral_conditions.js --apply --confirm \
  --project=proxi-play-odzp2e --published-by=users/<uid admin> \
  --reason="Conditions validées le 10/11/2026"
```

Le document de production contient `enabled: false` : la publication est
possible et ne change pas cette valeur.

## 7. Déploiement, plus tard et avec validation

1. Déployer la fonction `adminPublishMerchantReferralConditions` (nouvelle).
2. Comparer les règles de production au fichier 1.1.4 (voir
   `birthday-lock-1.1.4.md`), puis déployer les règles. Vérifier ensuite
   que l'interrupteur de l'Admin web fonctionne toujours.
3. Publier la version 1 (section 6).
4. Publier l'app 1.1.4.

## 8. Points restant à décider

1. **Durée de validité** des bons cadeaux, **délai de remise** et
   **fractionnement** : non décidés, absents du texte.
2. **Date d'entrée en vigueur différée.** En V1, une version entre en
   vigueur à sa publication. Faut-il pouvoir programmer une date future ?
   L'app devrait alors afficher la version en vigueur jusqu'à cette date.
3. **Enregistrer la version des conditions dans chaque parrainage**
   (`conditions_version`). Ce serait plus direct que le calcul par date,
   mais cela modifie la création des parrainages, dont celle du parcours
   Stripe. Non fait.
4. **Résumé de la page** (« Lorsqu'il a réglé son premier abonnement, vous
   recevez 50 €… »). Il reste figé dans l'app : faut-il le rendre
   dynamique lui aussi ?
5. **Texte de l'interrupteur Admin** : corrigé dans l'Admin par le commit
   `bdf1fc3`, branche `fix/merchant-referral-closed-by-default`, empilée
   sur `05808da`. Un réglage absent ou non booléen s'y affiche désormais
   « Programme désactivé ».
6. **La phrase « Les modalités de remise des bons cadeaux restent à
   préciser »**, présente dans l'ancien texte, n'est pas dans le texte
   validé, qui a été repris tel quel.
