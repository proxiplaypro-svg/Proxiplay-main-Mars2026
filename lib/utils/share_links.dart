const String shareLinkBase = 'https://onelink.to/jx4ee7';
const String shareSlogan = 'On a tout à gagner à jouer la proximité';

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

String buildAppShareText({
  String? title,
  String? description,
  String? referralCode,
}) {
  final buffer = StringBuffer();
  final normalizedTitle = title?.trim() ?? '';
  final normalizedDescription = description?.trim() ?? '';

  buffer.writeln(shareSlogan);

  if (normalizedTitle.isNotEmpty || normalizedDescription.isNotEmpty) {
    buffer.writeln();
    if (normalizedTitle.isNotEmpty) {
      buffer.writeln(normalizedTitle);
    }
    if (normalizedDescription.isNotEmpty) {
      if (normalizedTitle.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln(normalizedDescription);
    }
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
