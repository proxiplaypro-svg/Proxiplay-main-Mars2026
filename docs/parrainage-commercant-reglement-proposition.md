# Parrainage commerçant — proposition de règlement (à valider)

> Projet de travail. **Aucun texte de l'application n'a été modifié.** Les passages
> `[À DÉFINIR]` sont des décisions à prendre par ProxiPlay (et, si besoin, à faire
> relire juridiquement) ; ils ne doivent pas être remplacés par des hypothèses.

## 1. Textes actuellement affichés dans l'app 1.1.3

| Emplacement | Texte |
|---|---|
| `merchant_referral_conditions.dart` (fenêtre « Conditions du programme ») | « Le parrain peut être un joueur ou un commerçant ProxiPlay. Il reçoit 50 € en bons cadeaux, jamais en espèces, lorsque le commerçant parrainé a réglé son premier abonnement et que le parrainage est validé. Le commerçant renseigne le code en créant son compte ProxiPlay. Un même compte commerçant ne peut être parrainé qu'une fois. **Les modalités de remise des bons cadeaux restent à préciser.** Les droits des parrainages antérieurs restent soumis aux conditions qui leur étaient applicables. » |
| `parrainage_commercant_page_widget.dart` l. 173 | « Lorsqu'il a réglé son premier abonnement, vous recevez 50 € en bons cadeaux après validation. » |
| `parrainage_commercant_page_widget.dart` l. 198 / 209 | « 50 € en bons cadeaux » ; « Recevez 50 € en bons cadeaux lorsque le commerçant a réglé son premier abonnement et que le parrainage est validé. » |

**Clause incomplète affichée aux utilisateurs :** « Les modalités de remise des bons cadeaux restent à préciser. »

## 2. Ce que le serveur applique déjà (constaté dans le code, non déployé en totalité)

- Montant : 50 € (`kRewardAmountCents = 5000`), en bons cadeaux, jamais en espèces.
- Une seule prime par **compte** commerçant parrainé (identifiant du parrainage = compte), quel que soit le nombre d'enseignes.
- Le code est saisi à la création du compte commerçant.
- Éligibilité uniquement au **premier paiement confirmé** de l'abonnement (Stripe `invoice.paid`, `subscription_create`), jamais à la saisie du code ni à la création du compte ; ou confirmation manuelle par l'administration tant que Stripe n'est pas opérationnel.
- Étapes : `linked` → `eligible` → `approved` (validation administrateur) → `paid` (référence de remise saisie). Refus possible avec motif (`rejected`).
- Annulation d'abonnement, remboursement ou litige **avant** approbation : parrainage annulé. Après approbation ou versement : aucune récupération automatique.
- Parrain exclu (compte exclu des gains) : code refusé.
- Programme désactivable (`app_config/merchant_referral.enabled`, actuellement `false` en production).

## 3. Décisions à prendre avant toute modification du texte

1. **Modalités de remise** : nature des bons (enseigne(s), carte cadeau, partenaire…) `[À DÉFINIR]`, mode d'envoi (e-mail, courrier, remise en main propre) `[À DÉFINIR]`.
2. **Délai** : délai de validation après le premier paiement `[À DÉFINIR]` et délai de remise après validation `[À DÉFINIR]`.
3. **Validation** : qui valide (administration ProxiPlay) et sur quels critères vérifiables `[À DÉFINIR]` ; motifs de refus publiés ou non `[À DÉFINIR]`.
4. **Premier abonnement** : durée minimale d'abonnement ou délai de rétractation avant validation `[À DÉFINIR]` ; sort d'un remboursement intervenant après versement `[À DÉFINIR]` (le serveur ne récupère rien automatiquement).
5. **Validité des bons** : durée de validité et conditions d'utilisation `[À DÉFINIR]`.
6. **Plafond** : nombre maximal de parrainages récompensés par parrain et par période `[À DÉFINIR]` (aucun plafond n'est appliqué aujourd'hui).
7. **Exclusions** : parrainage de son propre commerce ou d'un commerce lié (même gérant, même SIRET) `[À DÉFINIR]` — aucun contrôle dédié n'existe aujourd'hui en dehors de l'unicité par compte ; salariés/associés de ProxiPlay `[À DÉFINIR]`.
8. **Fiscalité/déclaratif** éventuel pour un parrain commerçant `[À DÉFINIR — avis comptable]`.
9. **Durée du programme et modification** : date de début, possibilité d'arrêt, préavis `[À DÉFINIR]` (la phrase sur les droits des parrainages antérieurs existe déjà).
10. **Contact et réclamation** : adresse et délai de réponse `[À DÉFINIR]`.
11. **Données personnelles** : renvoi à la politique de confidentialité pour les données du parrain et du filleul `[À VALIDER]`.

## 4. Structure proposée du règlement (une fois les décisions prises)

1. Objet et organisateur
2. Qui peut parrainer / qui peut être parrainé (et exclusions)
3. Fonctionnement (code, saisie à la création du compte)
4. Conditions d'obtention (premier abonnement payé, validation, délais)
5. Récompense (montant, nature, remise, validité, absence d'équivalent en espèces)
6. Annulation, remboursement, fraude
7. Plafonds
8. Durée et modification du programme
9. Données personnelles
10. Contact et réclamations

## 5. Mise en œuvre après validation

- Remplacer le texte de `MerchantReferralConditionsDialog` par un résumé court + lien vers le règlement complet (page légale ProxiPlay, ouverte comme les autres pages légales).
- Aligner les deux accroches de `parrainage_commercant_page_widget.dart` sur les mêmes termes.
- Ne pas activer `app_config/merchant_referral.enabled` en production avant publication du règlement.
