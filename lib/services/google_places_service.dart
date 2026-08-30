import 'package:cloud_functions/cloud_functions.dart';

import '/backend/google_places/google_place_search_result.dart';

/// Recherche d'etablissements Google (Places API) pour l'association
/// manuelle commercant <-> fiche Google. L'appel passe par une Cloud
/// Function (`searchGooglePlaces`) qui garde la cle Google Places cote
/// serveur : elle n'est jamais presente dans le code ni le bundle client.
class GooglePlacesService {
  GooglePlacesService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<List<GooglePlaceSearchResult>> searchEstablishments(
    String query,
  ) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final response = await _functions
        .httpsCallable('searchGooglePlaces')
        .call(<String, dynamic>{'query': trimmedQuery});

    final data = response.data;
    final rawResults = data is Map ? data['results'] : null;
    if (rawResults is! List) {
      return const [];
    }

    return rawResults
        .whereType<Map>()
        .map((entry) =>
            GooglePlaceSearchResult.fromMap(Map<String, dynamic>.from(entry)))
        .where((result) => result.placeId.isNotEmpty)
        .toList();
  }
}
