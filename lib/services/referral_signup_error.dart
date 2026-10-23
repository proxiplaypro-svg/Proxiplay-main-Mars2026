/// Player-facing result of a referral signup error, without sensitive input.
class ReferralSignupError {
  const ReferralSignupError(this.message, {this.accountCreated = false});
  final String message;
  final bool accountCreated;
}

ReferralSignupError describeReferralSignupError(String code, Object? details) {
  final data = details is Map ? details : const {};
  if (data['reason'] == 'referral_unavailable' && data['accountCreated'] == true) {
    return const ReferralSignupError(
      'Votre compte a \u00e9t\u00e9 cr\u00e9\u00e9, mais ce code vient d\u2019\u00eatre utilis\u00e9. '
      'Vous pouvez vous connecter avec votre adresse e-mail et votre mot de passe, sans parrainage.',
      accountCreated: true,
    );
  }
  if (data['reason'] == 'email_exists') {
    return const ReferralSignupError('Cette adresse e-mail poss\u00e8de d\u00e9j\u00e0 un compte. Connectez-vous avec vos identifiants.');
  }
  if (code == 'not-found') {
    return const ReferralSignupError('Ce code de parrainage est invalide. V\u00e9rifiez-le ou inscrivez-vous sans code.');
  }
  if (data['reason'] == 'referral_unavailable') {
    return const ReferralSignupError('Ce code de parrainage a d\u00e9j\u00e0 \u00e9t\u00e9 utilis\u00e9. Utilisez un autre code ou inscrivez-vous sans code.');
  }
  if (code == 'resource-exhausted') {
    return const ReferralSignupError('Trop de tentatives. Patientez une minute avant de r\u00e9essayer.');
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return const ReferralSignupError('Connexion interrompue. R\u00e9essayez avec la m\u00eame adresse et le m\u00eame code. Si votre compte est cr\u00e9\u00e9, vous pourrez aussi vous connecter.');
  }
  return const ReferralSignupError('L\u2019inscription n\u2019a pas pu aboutir. R\u00e9essayez ou connectez-vous si votre compte existe d\u00e9j\u00e0.');
}
