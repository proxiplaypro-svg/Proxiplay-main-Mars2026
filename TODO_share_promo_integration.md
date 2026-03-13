# TODO Share Promo Integration

1. Installer les dependances Node dans `firebase/functions`.
2. Compiler le module TypeScript avec `npm run compile`.
3. Deployer `functions`, `firestore.rules` et `firestore.indexes.json`.
4. Ajouter le custom claim `admin: true` aux comptes admin Firebase Auth.
5. Integrer `SharePromoService.getSharePromoState()` dans le `SharePromoBanner` de la home joueur.
6. Brancher `SharePromoService.createReferral()` sur le flow de partage depuis `share_jeu_page`.
7. Brancher `SharePromoService.registerReferralAcceptance()` sur l entree par lien/code d invitation.
8. Ajouter les routes Flutter pour `CampaignSharePromoAdminPageWidget` et `SharePromoStatsAdminPageWidget`.
9. Ajouter des actions admin depuis `HomeAdminPageWidget` vers les deux nouvelles pages.
10. Etendre `applyRewardToUser()` si la recompense finale n est pas `remaining_part`.
