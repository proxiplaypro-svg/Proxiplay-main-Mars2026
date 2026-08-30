/// Resultat normalise d'une recherche Google Places, tel que renvoye par la
/// Cloud Function `searchGooglePlaces`. Volontairement minimal : seuls les
/// champs necessaires pour l'association manuelle commercant <-> fiche
/// Google sont exposes ici (pas de note, avis, horaires, etc.).
class GooglePlaceSearchResult {
  const GooglePlaceSearchResult({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
  });

  final String placeId;
  final String name;
  final String formattedAddress;

  factory GooglePlaceSearchResult.fromMap(Map<String, dynamic> map) {
    return GooglePlaceSearchResult(
      placeId: (map['placeId'] as String?)?.trim() ?? '',
      name: (map['name'] as String?)?.trim() ?? '',
      formattedAddress: (map['formattedAddress'] as String?)?.trim() ?? '',
    );
  }
}
