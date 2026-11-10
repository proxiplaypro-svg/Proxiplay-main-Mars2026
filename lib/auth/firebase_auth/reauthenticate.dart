import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '/auth/account_deletion.dart';

/// Codes renvoyes quand le joueur ferme lui-meme la fenetre du fournisseur.
const Set<String> _kCancelledCodes = {
  'canceled',
  'cancelled',
  'web-context-canceled',
  'popup-closed-by-user',
  'cancelled-popup-request',
};

/// Reauthentifie le joueur connecte avec son propre mode de connexion avant
/// une action sensible (suppression du compte).
///
/// Renvoie true si Firebase a confirme l'identite, false si le joueur a
/// annule ; leve une [FirebaseAuthException] en cas d'echec (identifiants
/// refuses, autre compte choisi, mode non pris en charge...).
Future<bool> reauthenticateCurrentUser(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw FirebaseAuthException(code: 'no-current-user');
  }
  final method = reauthMethodFor(user.providerData.map((p) => p.providerId));
  try {
    switch (method) {
      case ReauthMethod.password:
        final email = user.email;
        if (email == null || email.isEmpty) {
          throw FirebaseAuthException(code: 'reauth-unsupported');
        }
        final password = await _askPassword(context);
        if (password == null || password.isEmpty) return false;
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
        return true;
      case ReauthMethod.google:
        if (kIsWeb) {
          await user.reauthenticateWithPopup(GoogleAuthProvider());
          return true;
        }
        final googleSignIn = GoogleSignIn(scopes: ['profile', 'email']);
        try {
          await googleSignIn.signOut();
        } catch (_) {}
        final account = await googleSignIn.signIn();
        if (account == null) return false;
        final tokens = await account.authentication;
        // Un autre compte Google que celui du joueur : Firebase leve
        // user-mismatch, la suppression n'a pas lieu.
        await user.reauthenticateWithCredential(GoogleAuthProvider.credential(
          accessToken: tokens.accessToken,
          idToken: tokens.idToken,
        ));
        return true;
      case ReauthMethod.apple:
        final provider = AppleAuthProvider();
        if (kIsWeb) {
          await user.reauthenticateWithPopup(provider);
        } else {
          await user.reauthenticateWithProvider(provider);
        }
        return true;
      case ReauthMethod.unsupported:
        throw FirebaseAuthException(code: 'reauth-unsupported');
    }
  } on FirebaseAuthException catch (error) {
    if (_kCancelledCodes.contains(error.code)) return false;
    rethrow;
  }
}

Future<String?> _askPassword(BuildContext context) async {
  if (!context.mounted) return null;
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(kReauthPasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kReauthPasswordMessage),
            const SizedBox(height: 12.0),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Mot de passe'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Confirmer la suppression'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
