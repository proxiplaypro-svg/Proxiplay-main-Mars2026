# Nettoyage automatique des empreintes publicitaires (TTL)

**État : préparé, non activé.**

## Ce qui est concerné

`recordAdEvent` (firebase/functions/ad_system.js) écrit deux types de documents techniques, sans donnée personnelle (empreintes salées et non réversibles) :

| Collection | Contenu | Durée utile | Champ d'expiration |
|---|---|---|---|
| `_ad_exposures` | dernière impression / dernier clic d'une personne pour un emplacement et une campagne | 30 min (fenêtre de dédoublonnage) | `expires_at` = écriture + 60 min |
| `_ad_event_rate` | compteur de débit par source, sur une minute | 1 min | `expires_at` = écriture + 2 min |

Sans politique TTL, ces documents ne sont jamais supprimés. Ils restent petits et sans effet sur le comptage, puisque le code ignore les fenêtres expirées, mais ils s'accumulent.

## Activation (après accord, en production)

Firestore supprime alors automatiquement chaque document dans les 24 h qui suivent sa date `expires_at`. Ce délai est propre à Firestore et sans conséquence ici.

Deux commandes, une par collection :

```
gcloud firestore fields ttls update expires_at --collection-group=_ad_exposures --enable-ttl --project=proxi-play-odzp2e
gcloud firestore fields ttls update expires_at --collection-group=_ad_event_rate --enable-ttl --project=proxi-play-odzp2e
```

Autre méthode : recopier les deux entrées de `firebase/firestore.ttl.ads.json` dans le tableau `fieldOverrides` de `firebase/firestore.indexes.json`, puis lancer `firebase deploy --only firestore:indexes`. **Attention** : ce déploiement applique aussi tout l'état local des index. Les commandes `gcloud` ci-dessus sont plus ciblées.

## Vérification

```
gcloud firestore fields ttls list --project=proxi-play-odzp2e
```

L'état doit passer à `ACTIVE`, ce qui peut prendre quelques minutes.

## Retour arrière

```
gcloud firestore fields ttls update expires_at --collection-group=_ad_exposures --disable-ttl --project=proxi-play-odzp2e
gcloud firestore fields ttls update expires_at --collection-group=_ad_event_rate --disable-ttl --project=proxi-play-odzp2e
```

## Prérequis

- `recordAdEvent` déployée dans sa nouvelle version : l'ancienne n'écrit pas ces collections.
- Le TTL ne supprime que les documents qui ont un champ `expires_at` de type horodatage, ce qui est toujours le cas ici.
