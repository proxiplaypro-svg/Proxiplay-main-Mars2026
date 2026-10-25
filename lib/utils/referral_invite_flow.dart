import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// "Inviter un ami" (player referral), 26/10/2026: players of 1.1.1 saw
/// "Le partage n'a pas pu être ouvert" while createReferral succeeded, and
/// each new tap created one more unused invitation. This flow tells the
/// failing step apart, keeps an invitation that was not sent for the next
/// tap, and lets the player copy its link when the share sheet fails.
/// Referral rules are unchanged: a code is still single-use on the server.

enum ReferralInviteStage { createReferral, buildLink, openShare }

/// Technical cause of a failed step, without personal data: exception type,
/// error code and a short message with codes, links and addresses removed.
class ReferralInviteFailure {
  const ReferralInviteFailure({
    required this.stage,
    required this.errorType,
    required this.detail,
    this.errorCode,
  });

  final ReferralInviteStage stage;
  final String errorType;
  final String? errorCode;
  final String detail;

  String get logLine => '[REFERRAL_INVITE] failed stage=${stage.name} '
      'type=$errorType code=${errorCode ?? '-'} detail=$detail';

  Map<String, Object> get analyticsParameters => {
        'stage': stage.name,
        'error_type': _cap(errorType, 40),
        'error_code': _cap(errorCode ?? '-', 40),
      };

  static ReferralInviteFailure of(
    ReferralInviteStage stage,
    Object error, {
    String? secret,
  }) {
    String? code;
    String? message;
    if (error is FirebaseFunctionsException) {
      code = error.code;
      message = error.message;
    } else if (error is PlatformException) {
      code = error.code;
      message = error.message;
    } else {
      message = error.toString();
    }
    return ReferralInviteFailure(
      stage: stage,
      errorType: error.runtimeType.toString(),
      errorCode: code,
      detail: sanitizeInviteDiagnostic(message, secret: secret),
    );
  }
}

String _cap(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

/// Removes the invite code, links, e-mail addresses and long identifiers
/// from a technical message, and caps its length.
String sanitizeInviteDiagnostic(String? raw, {String? secret}) {
  var value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (secret != null && secret.isNotEmpty) {
    value = value.replaceAll(secret, '<code>');
  }
  value = value
      .replaceAll(RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<url>')
      .replaceAll(RegExp(r'\S+@\S+'), '<email>')
      .replaceAll(RegExp(r'\b[A-Za-z0-9_-]{20,}\b'), '<id>')
      .replaceAll(RegExp(r'\b[0-9A-F]{8}\b'), '<code>');
  return value.isEmpty ? '-' : _cap(value, 160);
}

/// An invitation created on the server: its code is single-use.
class PreparedReferralInvite {
  const PreparedReferralInvite({
    required this.code,
    required this.link,
    required this.text,
    required this.createdAt,
  });

  final String code;
  final String link;
  final String text;
  final DateTime createdAt;
}

/// Invitations created but not handed to anyone yet (share failed or was
/// cancelled), per account, in memory. Reused instead of creating a new one.
class UnsentReferralInvites {
  UnsentReferralInvites({this.maxAge = const Duration(hours: 1)});

  final Duration maxAge;
  final Map<String, PreparedReferralInvite> _byAccount = {};

  PreparedReferralInvite? get(String accountId, DateTime now) {
    final invite = _byAccount[accountId];
    if (invite == null) return null;
    if (now.difference(invite.createdAt) > maxAge) {
      _byAccount.remove(accountId);
      return null;
    }
    return invite;
  }

  void keep(String accountId, PreparedReferralInvite invite) =>
      _byAccount[accountId] = invite;

  /// The invitation may have reached someone (shared, copied): never reuse it.
  void handedOver(String accountId) => _byAccount.remove(accountId);
}

final UnsentReferralInvites unsentReferralInvites = UnsentReferralInvites();

enum ReferralInviteStatus {
  /// The share sheet closed after the player picked an app.
  shared,

  /// The player closed the share sheet: the invitation is kept for next time.
  dismissed,

  /// The platform could not tell (older iOS): treated as possibly sent.
  uncertain,

  /// A step failed; see [ReferralInviteOutcome.failure].
  failed,
}

class ReferralInviteOutcome {
  const ReferralInviteOutcome(
    this.status, {
    this.invite,
    this.failure,
    this.reused = false,
  });

  final ReferralInviteStatus status;

  /// Set whenever an invitation exists, also when only its share failed:
  /// its link can then be copied.
  final PreparedReferralInvite? invite;
  final ReferralInviteFailure? failure;
  final bool reused;

  bool get canCopyLink =>
      status == ReferralInviteStatus.failed && invite != null;
}

/// A built invitation is usable only with a code and a link carrying it.
bool isUsableReferralInvite(PreparedReferralInvite invite) {
  final uri = Uri.tryParse(invite.link);
  return invite.code.isNotEmpty &&
      uri != null &&
      uri.hasScheme &&
      invite.link.contains(invite.code) &&
      invite.text.isNotEmpty;
}

/// Runs one "Inviter un ami" tap. The platform calls are injected so every
/// failing step can be tested.
Future<ReferralInviteOutcome> runReferralInvite({
  required String accountId,
  required Future<Map<String, dynamic>> Function() createReferral,
  required PreparedReferralInvite Function(
          Map<String, dynamic> response, DateTime now)
      buildInvite,
  required Future<ShareResultStatus> Function(String text) share,
  required DateTime now,
  UnsentReferralInvites? store,
  void Function(ReferralInviteFailure failure)? onFailure,
}) async {
  final unsent = store ?? unsentReferralInvites;
  ReferralInviteOutcome fail(ReferralInviteFailure failure,
      [PreparedReferralInvite? invite, bool reused = false]) {
    onFailure?.call(failure);
    return ReferralInviteOutcome(ReferralInviteStatus.failed,
        invite: invite, failure: failure, reused: reused);
  }

  var invite = unsent.get(accountId, now);
  final reused = invite != null;
  if (invite == null) {
    final Map<String, dynamic> response;
    try {
      response = await createReferral();
    } catch (error) {
      return fail(
          ReferralInviteFailure.of(ReferralInviteStage.createReferral, error));
    }
    try {
      invite = buildInvite(response, now);
    } catch (error) {
      return fail(ReferralInviteFailure.of(ReferralInviteStage.buildLink, error,
          secret: '${response['inviteCode'] ?? ''}'));
    }
    if (!isUsableReferralInvite(invite)) {
      return fail(const ReferralInviteFailure(
        stage: ReferralInviteStage.buildLink,
        errorType: 'InvalidInvite',
        detail: 'missing code or link',
      ));
    }
    unsent.keep(accountId, invite);
  }

  final ShareResultStatus status;
  try {
    status = await share(invite.text);
  } catch (error) {
    // The invitation stays unsent: its link can be copied, and the next tap
    // reuses it instead of creating another one.
    return fail(
        ReferralInviteFailure.of(ReferralInviteStage.openShare, error,
            secret: invite.code),
        invite,
        reused);
  }
  switch (status) {
    case ShareResultStatus.success:
      unsent.handedOver(accountId);
      return ReferralInviteOutcome(ReferralInviteStatus.shared,
          invite: invite, reused: reused);
    case ShareResultStatus.dismissed:
      return ReferralInviteOutcome(ReferralInviteStatus.dismissed,
          invite: invite, reused: reused);
    case ShareResultStatus.unavailable:
      unsent.handedOver(accountId);
      return ReferralInviteOutcome(ReferralInviteStatus.uncertain,
          invite: invite, reused: reused);
  }
}
