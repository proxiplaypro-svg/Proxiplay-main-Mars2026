import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_util.dart';
import '/app_state.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/auth/user_profile/user_profile_completion.dart';
import 'account_routing_logic.dart';
export 'account_routing_logic.dart' show AuthenticatedHomeTarget;

const _kLoginRouteName = 'LoginPage';
const _kHomeJoueurRouteName = 'HomeJoueurPage';
const _kHomeCommercantRouteName = 'HomeCommercantPage';
const _kHomeAdminRouteName = 'HomeAdminPage';
const _kInscriptionInformationsRouteName = 'InscriptionInformationsPage';
const _kWaitingValidationRouteName = 'WaitingValidationPage';
const _kRejetInscriptionRouteName = 'rejetInscriptionPage';

class AuthenticatedHomeResolution {
  const AuthenticatedHomeResolution({
    required this.target,
    required this.reason,
    required this.uid,
    required this.rawRole,
    required this.normalizedRole,
    required this.claimRole,
    required this.claimsSummary,
    required this.hasEnseigne,
    required this.playerSignals,
    required this.merchantSignals,
    required this.accountStatus,
    required this.documentExists,
    required this.usedRepair,
    required this.cachedRole,
    required this.rawRoleSources,
  });

  final AuthenticatedHomeTarget target;
  final String reason;
  final String uid;
  final String rawRole;
  final Roles? normalizedRole;
  final Roles? claimRole;
  final String claimsSummary;
  final bool hasEnseigne;
  final List<String> playerSignals;
  final List<String> merchantSignals;
  final AccountStatus? accountStatus;
  final bool documentExists;
  final bool usedRepair;
  final Roles? cachedRole;
  final Map<String, dynamic> rawRoleSources;

  String get routeName {
    switch (target) {
      case AuthenticatedHomeTarget.joueurHome:
        return _kHomeJoueurRouteName;
      case AuthenticatedHomeTarget.commercantHome:
        return _kHomeCommercantRouteName;
      case AuthenticatedHomeTarget.adminHome:
        return _kHomeAdminRouteName;
      case AuthenticatedHomeTarget.pendingInfo:
        return _kInscriptionInformationsRouteName;
      case AuthenticatedHomeTarget.waitingValidation:
        return _kWaitingValidationRouteName;
      case AuthenticatedHomeTarget.rejected:
        return _kRejetInscriptionRouteName;
      case AuthenticatedHomeTarget.login:
      case AuthenticatedHomeTarget.routingIssue:
        return _kLoginRouteName;
    }
  }

  bool get shouldShowRoutingIssue =>
      target == AuthenticatedHomeTarget.routingIssue;
}

String _trimmedString(dynamic value) => value is String ? value.trim() : '';

Roles? _normalizeRoleValue(dynamic value) {
  final normalized = _trimmedString(value).toLowerCase();
  switch (normalized) {
    case 'joueur':
    case 'player':
    case 'participant':
      return Roles.joueur;
    case 'commercant':
    case 'merchant':
    case 'professional':
    case 'pro':
      return Roles.commercant;
    case 'admin':
      return Roles.admin;
    default:
      return null;
  }
}

AccountStatus? _readRawAccountStatus(Map<String, dynamic> data) {
  final rawStatus = data['account_status'];
  if (rawStatus is AccountStatus) {
    return rawStatus;
  }
  return deserializeEnum<AccountStatus>(rawStatus?.toString());
}

Map<String, dynamic> _extractRoleSources(Map<String, dynamic> data) {
  return <String, dynamic>{
    'user_role': data['user_role'],
    'userRole': data['userRole'],
    'role': data['role'],
    'user_type': data['user_type'],
    'accountType': data['accountType'],
    'isProfessional': data['isProfessional'],
  };
}

dynamic _firstRoleCandidate(Map<String, dynamic> roleSources) {
  for (final key in <String>[
    'user_role',
    'userRole',
    'role',
    'user_type',
    'accountType',
  ]) {
    final value = roleSources[key];
    if (_trimmedString(value).isNotEmpty) {
      return value;
    }
  }
  return null;
}

List<String> _collectPlayerSignals(Map<String, dynamic> data) {
  final signals = <String>[];
  if (data.containsKey('remaining_part')) {
    signals.add('remaining_part');
  }
  if (data.containsKey('part_last_update')) {
    signals.add('part_last_update');
  }
  if (data.containsKey('allGamesAccessUntil')) {
    signals.add('allGamesAccessUntil');
  }
  return signals;
}

bool hasCachedMerchantRoutingConflict(UsersRecord? user) {
  if (user == null || user.userRole != Roles.commercant) {
    return false;
  }
  final playerSignals = <String>[];
  if (user.hasRemainingPart()) {
    playerSignals.add('remaining_part');
  }
  if (user.hasPartLastUpdate()) {
    playerSignals.add('part_last_update');
  }
  if (user.hasAllGamesAccessUntil()) {
    playerSignals.add('allGamesAccessUntil');
  }
  final merchantSignals = <String>[];
  if (user.hasProfessionalCategory()) {
    merchantSignals.add('professional_category');
  }
  if (user.accountStatus == AccountStatus.pendingValidation ||
      user.accountStatus == AccountStatus.pendingInfo ||
      user.accountStatus == AccountStatus.rejected) {
    merchantSignals.add('account_status');
  }
  return hasMerchantPlayerSignalConflict(
    role: user.userRole,
    playerSignals: playerSignals,
    merchantSignals: merchantSignals,
  );
}

List<String> _collectMerchantSignals({
  required Map<String, dynamic> data,
  required bool hasEnseigne,
  required Roles? claimRole,
}) {
  final signals = <String>[];
  if (hasEnseigne) {
    signals.add('enseigne_owner');
  }
  if (_trimmedString(data['professional_category']).isNotEmpty) {
    signals.add('professional_category');
  }
  if (_trimmedString(data['account_status']) == 'pendingValidation') {
    signals.add('pendingValidation');
  }
  if (claimRole == Roles.commercant) {
    signals.add('claim_commercant');
  }
  final isProfessionalFlag = data['isProfessional'];
  if (isProfessionalFlag == true) {
    signals.add('isProfessional=true');
  }
  return signals;
}

String summarizeClaims(Map<String, dynamic> claims) {
  if (claims.isEmpty) {
    return '<empty>';
  }
  return claims.entries.map((entry) => '${entry.key}=${entry.value}').join(', ');
}

Future<bool> _hasOwnedEnseigne(DocumentReference? userRef) async {
  if (userRef == null) {
    return false;
  }
  final snapshot = await EnseignesRecord.collection
      .where('owner', isEqualTo: userRef)
      .limit(1)
      .get();
  return snapshot.docs.isNotEmpty;
}

Future<DocumentSnapshot<Map<String, dynamic>>?> _readCurrentUserSnapshot({
  bool preferServer = false,
}) async {
  final userRef = currentUserReference;
  if (userRef == null) {
    return null;
  }

  final typedRef = userRef.withConverter<Map<String, dynamic>>(
    fromFirestore: (snapshot, _) => snapshot.data() ?? <String, dynamic>{},
    toFirestore: (value, _) => value,
  );

  if (!preferServer) {
    return typedRef.get();
  }

  try {
    return await typedRef.get(const GetOptions(source: Source.server));
  } catch (_) {
    return typedRef.get();
  }
}

Future<UsersRecord?> _repairMissingPlayerRoleIfSafe({
  required User firebaseUser,
  required List<String> playerSignals,
  required List<String> merchantSignals,
  required String source,
}) async {
  if (playerSignals.isEmpty || merchantSignals.isNotEmpty) {
    return null;
  }

  if (kDebugMode) {
    debugPrint(
      '[AccountRouting][$source] repairing_missing_role '
      'reason=player_signals_without_merchant_signals '
      'playerSignals=${playerSignals.join(",")} '
      'merchantSignals=${merchantSignals.join(",")}',
    );
  }

  return ensureUserDocumentInitialized(
    firebaseUser,
    roleHint: Roles.joueur,
    authProvider: 'ROLE_RECOVERY',
    source: source,
  );
}

Future<bool> _repairMerchantLegacyPlayerSignalsIfSafe({
  required Roles? role,
  required List<String> playerSignals,
  required List<String> merchantSignals,
  required String source,
}) async {
  if (role != Roles.commercant ||
      playerSignals.isEmpty ||
      merchantSignals.isEmpty ||
      currentUserReference == null) {
    return false;
  }

  if (kDebugMode) {
    debugPrint(
      '[AccountRouting][$source] repairing_merchant_legacy_player_signals '
      'playerSignals=${playerSignals.join(",")} '
      'merchantSignals=${merchantSignals.join(",")}',
    );
  }

  await currentUserReference!.update(<String, dynamic>{
    'remaining_part': FieldValue.delete(),
    'part_last_update': FieldValue.delete(),
    'allGamesAccessUntil': FieldValue.delete(),
  });
  await refreshCurrentUserDocument();
  return true;
}

Future<AuthenticatedHomeResolution> resolveAuthenticatedHome({
  String source = 'unknown',
  bool preferServer = false,
  bool allowRepair = true,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (isGuestOrAnonymous) {
    return const AuthenticatedHomeResolution(
      target: AuthenticatedHomeTarget.joueurHome,
      reason: 'guest_or_anonymous',
      uid: '',
      rawRole: '',
      normalizedRole: null,
      claimRole: null,
      claimsSummary: '<guest>',
      hasEnseigne: false,
      playerSignals: <String>[],
      merchantSignals: <String>[],
      accountStatus: null,
      documentExists: false,
      usedRepair: false,
      cachedRole: null,
      rawRoleSources: <String, dynamic>{},
    );
  }

  if (firebaseUser == null) {
    return const AuthenticatedHomeResolution(
      target: AuthenticatedHomeTarget.login,
      reason: 'firebase_user_missing',
      uid: '',
      rawRole: '',
      normalizedRole: null,
      claimRole: null,
      claimsSummary: '<unauthenticated>',
      hasEnseigne: false,
      playerSignals: <String>[],
      merchantSignals: <String>[],
      accountStatus: null,
      documentExists: false,
      usedRepair: false,
      cachedRole: null,
      rawRoleSources: <String, dynamic>{},
    );
  }

  final snapshot =
      await _readCurrentUserSnapshot(preferServer: preferServer);
  final data = snapshot?.data() ?? <String, dynamic>{};
  final roleSources = _extractRoleSources(data);
  final rawRoleValue = _firstRoleCandidate(roleSources);
  final rawRole = _trimmedString(rawRoleValue);
  final normalizedRole = _normalizeRoleValue(rawRoleValue);
  final cachedRole = currentUserDocument?.userRole;
  final tokenResult = await firebaseUser.getIdTokenResult();
  final claims = tokenResult.claims ?? <String, dynamic>{};
  final claimRole = _normalizeRoleValue(
    claims['user_role'] ?? claims['role'] ?? claims['accountType'],
  );
  final hasEnseigne = await _hasOwnedEnseigne(currentUserReference);
  final playerSignals = _collectPlayerSignals(data);
  final merchantSignals = _collectMerchantSignals(
    data: data,
    hasEnseigne: hasEnseigne,
    claimRole: claimRole,
  );
  final accountStatus = _readRawAccountStatus(data);

  var usedRepair = false;
  Roles? effectiveRole = normalizedRole;

  if (effectiveRole == null &&
      allowRepair &&
      snapshot != null &&
      snapshot.exists) {
    final repairedDoc = await _repairMissingPlayerRoleIfSafe(
      firebaseUser: firebaseUser,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      source: source,
    );
    if (repairedDoc != null) {
      usedRepair = true;
      effectiveRole = repairedDoc.userRole;
      await refreshCurrentUserDocument();
    }
  }

  if (allowRepair &&
      await _repairMerchantLegacyPlayerSignalsIfSafe(
        role: effectiveRole,
        playerSignals: playerSignals,
        merchantSignals: merchantSignals,
        source: source,
      )) {
    usedRepair = true;
    playerSignals.clear();
  }

  late final AuthenticatedHomeResolution resolution;
  final documentExists = snapshot != null && snapshot.exists;
  var target = resolveTargetFromResolvedRole(
    documentExists: documentExists,
    effectiveRole: effectiveRole,
    playerSignals: playerSignals,
    accountStatus: accountStatus,
  );

  // Point d'entree unique pour le rappel de completion de profil, quel que
  // soit le provider (email, Google, Apple, ...) : avant, seul le chemin de
  // connexion Google le faisait (logique dupliquee dans
  // inscription_page_widget.dart), donc un joueur inscrit par email qui
  // abandonnait la completion n'etait plus jamais relance a une connexion
  // suivante. On reutilise la cible/route existante `pendingInfo` (deja
  // routee vers InscriptionInformationsPage par tous les appelants) plutot
  // que d'ajouter une nouvelle cible a gerer partout.
  var isProfileCompletionRedirect = false;
  if (documentExists &&
      (target == AuthenticatedHomeTarget.joueurHome ||
          target == AuthenticatedHomeTarget.commercantHome) &&
      shouldOfferUserProfileCompletionPrompt(
        isProfileComplete:
            isUserProfileCompleteFromData(data, role: effectiveRole),
        hasDismissedPrompt: FFAppState()
            .hasDismissedProfileCompletionPromptForUid(firebaseUser.uid),
      )) {
    isProfileCompletionRedirect = true;
    FFAppState().update(() {
      FFAppState().offerProfileCompletionAfterLogin = true;
      FFAppState().profileCompletionReturnRouteName =
          target == AuthenticatedHomeTarget.commercantHome
              ? _kHomeCommercantRouteName
              : _kHomeJoueurRouteName;
    });
    target = AuthenticatedHomeTarget.pendingInfo;
  }

  if (!documentExists) {
    resolution = AuthenticatedHomeResolution(
      target: AuthenticatedHomeTarget.routingIssue,
      reason: 'user_document_missing',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: false,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else if (target == AuthenticatedHomeTarget.routingIssue &&
      hasMerchantPlayerSignalConflict(
        role: effectiveRole,
        playerSignals: playerSignals,
      )) {
    resolution = AuthenticatedHomeResolution(
      target: AuthenticatedHomeTarget.routingIssue,
      reason: 'merchant_role_conflicts_with_player_signals',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else if (target == AuthenticatedHomeTarget.routingIssue) {
    resolution = AuthenticatedHomeResolution(
      target: AuthenticatedHomeTarget.routingIssue,
      reason: rawRole.isEmpty ? 'role_missing' : 'role_invalid',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else if (isProfileCompletionRedirect) {
    resolution = AuthenticatedHomeResolution(
      target: target,
      reason: 'profile_completion_required',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else if (target == AuthenticatedHomeTarget.adminHome) {
    resolution = AuthenticatedHomeResolution(
      target: target,
      reason: 'explicit_admin_role',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else if (effectiveRole == Roles.commercant) {
    resolution = AuthenticatedHomeResolution(
      target: target,
      reason: 'explicit_merchant_role',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  } else {
    resolution = AuthenticatedHomeResolution(
      target: target,
      reason: 'explicit_player_role',
      uid: firebaseUser.uid,
      rawRole: rawRole,
      normalizedRole: effectiveRole,
      claimRole: claimRole,
      claimsSummary: summarizeClaims(claims),
      hasEnseigne: hasEnseigne,
      playerSignals: playerSignals,
      merchantSignals: merchantSignals,
      accountStatus: accountStatus,
      documentExists: true,
      usedRepair: usedRepair,
      cachedRole: cachedRole,
      rawRoleSources: roleSources,
    );
  }

  if (kDebugMode) {
    debugPrint(
      '[AccountRouting][$source] '
      'documentExists=${resolution.documentExists} '
      'usedRepair=${resolution.usedRepair} '
      'target=${resolution.target.name} '
      'reason=${resolution.reason} '
      'hasEnseigne=${resolution.hasEnseigne} '
      'playerSignalsCount=${resolution.playerSignals.length} '
      'merchantSignalsCount=${resolution.merchantSignals.length}',
    );
  }

  return resolution;
}

String? resolveCachedRoleGuardRedirectPath({
  required bool requireAdmin,
  required bool requireMerchant,
}) {
  final cachedUser = currentUserDocument;
  final role = cachedUser?.userRole;
  final hasConflict = hasCachedMerchantRoutingConflict(cachedUser);
  if (hasConflict && kDebugMode) {
    debugPrint(
      '[AccountRouting][cached_guard] blocking_merchant_route '
      'reason=merchant_role_conflicts_with_player_signals '
      'cachedRole=${role?.serialize() ?? "<null>"}',
    );
  }
  return resolveCachedRoleGuardRedirectPathForRole(
    requireAdmin: requireAdmin,
    requireMerchant: requireMerchant,
    role: role,
    hasMerchantConflict: hasConflict,
  );
}
