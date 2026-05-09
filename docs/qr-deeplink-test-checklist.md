# QR / Deep Link Test Checklist

- Tester un QR avec l app installee sur Android.
- Tester un QR sans l app installee sur Android.
- Tester un QR avec l app installee sur iOS TestFlight.
- Tester un QR sans l app installee sur iOS.
- Verifier `https://proxiplay.fr/.well-known/assetlinks.json`.
- Verifier `https://proxiplay.fr/.well-known/apple-app-site-association`.
- Verifier l absence de redirection sur les URLs `.well-known`.
- Verifier le retour post-login vers le jeu scanne.
- Verifier le partage de l image du QR code.
- Verifier un ancien jeu sans `qr_link`.
