import '/utils/share_links.dart';

/// Single source of the referral wording shown to the inviter and sent to the
/// invited friend. While a referral game runs (as reported by the server), a
/// validated referral gives the inviter a draw ticket instead of the "all
/// games until midnight" access, so no text may promise that access then.
///
/// `referralGameActive` is null when the state could not be loaded: no reward
/// is promised then, rather than a possibly wrong one.

const String referralGameInviteHeadline =
    'Invitez un ami et gagnez un ticket pour le tirage au sort !';
const String classicInviteHeadline =
    'Invitez un ami et jouez à tous les jeux jusqu’à minuit !';

String? referralInviteHeadline({required bool? referralGameActive}) {
  if (referralGameActive == null) return null;
  return referralGameActive ? referralGameInviteHeadline : classicInviteHeadline;
}

/// What the inviter earns, written for the invited friend.
String referralRewardForFriend({required bool? referralGameActive}) {
  if (referralGameActive == null) return '';
  return referralGameActive
      ? 'Quand ton inscription est validée, c’est moi qui gagne un ticket '
          'pour le tirage au sort.'
      : 'Ton inscription avec mon code me permet de jouer à tous les jeux '
          'jusqu’à minuit.';
}

String _codeHelp(String? referralCode) {
  final code = referralCode?.trim() ?? '';
  if (code.isEmpty) return '';
  return 'Code parrainage : $code\n'
      'Si le code ne se remplit pas automatiquement après installation, '
      'entre-le lors de ton inscription.';
}

String _paragraphs(List<String> parts) =>
    parts.where((part) => part.isNotEmpty).join('\n\n');

/// Message sent to a friend with a new invitation.
String buildReferralInviteMessage({
  required bool? referralGameActive,
  required String? referralCode,
}) {
  return buildAppShareText(
    title: 'Rejoins-moi sur ProxiPlay !',
    description: _paragraphs([
      'Inscris-toi sur ProxiPlay avec mon code de parrainage.',
      referralRewardForFriend(referralGameActive: referralGameActive),
      _codeHelp(referralCode),
    ]),
    referralCode: referralCode,
  );
}

/// Reminder sent to a friend whose invitation is still pending.
String buildReferralReminderMessage({
  required bool? referralGameActive,
  required String? referralCode,
}) {
  return buildAppShareText(
    title: 'Toujours partant pour ProxiPlay ?',
    description: _paragraphs([
      'Ton invitation t’attend toujours, rejoins-moi !',
      referralRewardForFriend(referralGameActive: referralGameActive),
    ]),
    referralCode: referralCode,
  );
}

/// Reads the server flag from a createReferral / getSharePromoState response.
/// An absent flag (older backend) keeps the classic wording.
bool referralGameActiveFrom(Map<String, dynamic>? response) =>
    response?['referralGameActive'] == true;
