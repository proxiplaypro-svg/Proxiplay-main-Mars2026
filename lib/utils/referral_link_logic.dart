// Player referral invitation link (https://play.proxiplay.fr/i?ref=CODE):
// decisions of the /i route and of the signup code field. Pure functions,
// tested without Firebase -- see test/referral_link_logic_test.dart. Never
// used by the merchant referral program (its links go to www.proxiplay.fr).

enum ReferralLinkTarget { wait, signup, home }

/// The invitation code carried by a link, normalized (trimmed, upper case),
/// or null when it cannot be an invitation code (missing, too short or long,
/// not hexadecimal): such a link opens nothing special. Invite codes are 8
/// hexadecimal characters; the bounds leave room without accepting junk.
String? referralCodeFromLink(String? raw) {
  final code = (raw ?? '').trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{4,32}$').hasMatch(code) ? code : null;
}

/// Where the /i route sends the player: the signup page with the code for a
/// visitor, the usual home for a signed-in account (the code never applies
/// to an existing account), nothing until the auth state is known.
ReferralLinkTarget resolveReferralLinkTarget({
  required bool authResolved,
  required bool authenticated,
}) {
  if (!authResolved) {
    return ReferralLinkTarget.wait;
  }
  return authenticated ? ReferralLinkTarget.home : ReferralLinkTarget.signup;
}

/// New text of the signup code field when the stored code changes while the
/// page is open (link received with the app already open), or null when the
/// field already shows it. What the player types is stored as they type, so
/// it is never overwritten by this.
String? referralFieldSyncText({
  required String fieldText,
  required String pendingCode,
}) {
  final pending = pendingCode.trim().toUpperCase();
  return fieldText.trim().toUpperCase() == pending ? null : pending;
}
