import 'dart:convert';

import 'package:http/http.dart' as http;

import '/utils/city_compat.dart';

class CityAutocompleteSuggestion {
  const CityAutocompleteSuggestion({
    required this.name,
    required this.inseeCode,
    required this.postalCodes,
  });

  final String name;
  final String inseeCode;
  final List<String> postalCodes;

  String get subtitle {
    if (postalCodes.isEmpty) {
      return inseeCode;
    }

    return '${postalCodes.join(', ')} · $inseeCode';
  }
}

class CityAutocompleteService {
  const CityAutocompleteService();

  Future<List<CityAutocompleteSuggestion>> searchCommunes(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) {
      return const [];
    }

    final uri = Uri.https('geo.api.gouv.fr', '/communes', {
      'nom': normalizedQuery,
      'boost': 'population',
      'limit': '8',
      'fields': 'nom,code,codesPostaux',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('city_autocomplete_http_${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final name = (item['nom'] as String? ?? '').trim();
          final inseeCode = normalizeInseeCode(item['code'] as String?);
          final postalCodes = ((item['codesPostaux'] as List?) ?? const [])
              .whereType<String>()
              .map((code) => code.trim())
              .where((code) => code.isNotEmpty)
              .toList(growable: false);

          if (name.isEmpty || inseeCode.isEmpty) {
            return null;
          }

          return CityAutocompleteSuggestion(
            name: name,
            inseeCode: inseeCode,
            postalCodes: postalCodes,
          );
        })
        .whereType<CityAutocompleteSuggestion>()
        .toList(growable: false);
  }
}
