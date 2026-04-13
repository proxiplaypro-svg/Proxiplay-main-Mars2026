String normalizeInseeCode(String? rawCode) {
  final digitsOnly = (rawCode ?? '').replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  return digitsOnly.trim().toUpperCase();
}

String resolveLegacyCityLabel({
  String? city,
  String? fallbackCity,
}) {
  final direct = (city ?? '').trim();
  if (direct.isNotEmpty) {
    return direct;
  }

  return (fallbackCity ?? '').trim();
}

Map<String, dynamic> createCityCompatData({
  String? city,
  String? cityInseeCode,
}) {
  final trimmedCity = (city ?? '').trim();
  final normalizedInseeCode = normalizeInseeCode(cityInseeCode);

  return <String, dynamic>{
    if (trimmedCity.isNotEmpty) 'city': trimmedCity,
    if (normalizedInseeCode.isNotEmpty) 'city_insee_code': normalizedInseeCode,
  };
}
