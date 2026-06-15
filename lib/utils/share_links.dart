const String shareLinkBase = 'https://onelink.to/jx4ee7';
const String gameQrLinkBase = 'https://play.proxiplay.fr/j';
const String proxiplayCustomScheme = 'proxiplay';
const String proxiplayAndroidPackageName = 'com.proxiplay.proxiplay';
const String proxiplayAndroidStoreUrl =
    'https://play.google.com/store/apps/details?id=$proxiplayAndroidPackageName';
const String proxiplayIosStoreUrl =
    'https://apps.apple.com/app/id6753818573';

const List<String> _referralParamCandidates = <String>[
  'ref',
  'inviteCode',
  'referralCode',
  'invite',
  'code',
];

const List<String> _nestedLinkParamCandidates = <String>[
  'link',
  'deep_link_value',
  'af_dp',
  'af_android_url',
  'af_ios_url',
];

String buildReferralShareLink([String? referralCode]) {
  final normalizedCode = _normalizeReferralCode(referralCode);
  if (normalizedCode == null) {
    return shareLinkBase;
  }

  final baseUri = Uri.parse(shareLinkBase);
  final queryParameters = Map<String, String>.from(baseUri.queryParameters)
    ..['ref'] = normalizedCode;
  return baseUri.replace(queryParameters: queryParameters).toString();
}

String buildGameQrLink(String gameId) {
  final normalizedGameId = gameId.trim();
  return '$gameQrLinkBase/$normalizedGameId';
}

String buildGameDeepLink(String gameId) {
  final normalizedGameId = gameId.trim();
  return '$proxiplayCustomScheme://game/$normalizedGameId';
}

String buildGameAndroidIntentUrl(String gameId) {
  final normalizedGameId = Uri.encodeComponent(gameId.trim());
  final encodedStoreUrl = Uri.encodeComponent(proxiplayAndroidStoreUrl);
  return 'intent://game/$normalizedGameId'
      '#Intent;scheme=$proxiplayCustomScheme;package=$proxiplayAndroidPackageName;'
      'S.browser_fallback_url=$encodedStoreUrl;end';
}

String buildAppShareText({
  String? title,
  String? description,
  String? referralCode,
}) {
  final buffer = StringBuffer();
  final normalizedTitle = title?.trim() ?? '';
  final normalizedDescription = description?.trim() ?? '';

  if (normalizedTitle.isNotEmpty) {
    buffer.writeln(normalizedTitle);
  }
  if (normalizedDescription.isNotEmpty) {
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }
    buffer.writeln(normalizedDescription);
  }
  if (buffer.isNotEmpty) {
    buffer.writeln();
  }
  buffer.write(buildReferralShareLink(referralCode));

  return buffer.toString().trim();
}

String? extractReferralCodeFromUri(Uri? uri) {
  if (uri == null) {
    return null;
  }

  final directMatch = _extractReferralCodeFromQuery(uri.queryParameters);
  if (directMatch != null) {
    return directMatch;
  }

  final fragment = uri.fragment.trim();
  if (fragment.isNotEmpty) {
    final fragmentUri = Uri.tryParse(fragment.startsWith('?') ? '/$fragment' : fragment);
    final fragmentMatch = extractReferralCodeFromUri(fragmentUri);
    if (fragmentMatch != null) {
      return fragmentMatch;
    }
  }

  for (final key in _nestedLinkParamCandidates) {
    final nestedValue = uri.queryParameters[key]?.trim();
    if (nestedValue == null || nestedValue.isEmpty) {
      continue;
    }

    final nestedUri = Uri.tryParse(Uri.decodeComponent(nestedValue));
    final nestedMatch = extractReferralCodeFromUri(nestedUri);
    if (nestedMatch != null) {
      return nestedMatch;
    }
  }

  return null;
}

String? _extractReferralCodeFromQuery(Map<String, String> queryParameters) {
  for (final key in _referralParamCandidates) {
    final value = _normalizeReferralCode(queryParameters[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _normalizeReferralCode(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.toUpperCase();
}
