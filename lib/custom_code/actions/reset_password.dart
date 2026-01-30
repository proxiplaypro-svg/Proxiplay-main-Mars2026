// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

// je veux retourne un dataype sous forme {status: string, message: string} pour le reset des mot de passe, tu dois mettre les message en francais
import 'package:firebase_auth/firebase_auth.dart';

Future<ResponseActionStatusStruct> resetPassword(String email) async {
  try {
    // Validation de l'email
    if (email.isEmpty) {
      return ResponseActionStatusStruct(
        status: 'error',
        message: 'L\'adresse email est requise',
      );
    }

    // Validation du format email
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      return ResponseActionStatusStruct(
        status: 'error',
        message: 'Format d\'adresse email invalide',
      );
    }

    // Envoi de l'email de réinitialisation
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

    return ResponseActionStatusStruct(
      status: 'success',
      message:
          'Un email de réinitialisation a été envoyé à votre adresse email',
    );
  } on FirebaseAuthException catch (e) {
    String errorMessage;

    switch (e.code) {
      case 'user-not-found':
        errorMessage = 'Aucun compte trouvé avec cette adresse email';
        break;
      case 'invalid-email':
        errorMessage = 'Adresse email invalide';
        break;
      case 'too-many-requests':
        errorMessage = 'Trop de tentatives. Veuillez réessayer plus tard';
        break;
      default:
        errorMessage = 'Une erreur est survenue lors de l\'envoi de l\'email';
    }

    return ResponseActionStatusStruct(
      status: 'error',
      message: errorMessage,
    );
  } catch (e) {
    return ResponseActionStatusStruct(
      status: 'error',
      message: 'Une erreur inattendue est survenue',
    );
  }
}
