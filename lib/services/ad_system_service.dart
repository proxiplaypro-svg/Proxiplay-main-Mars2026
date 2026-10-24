import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '/utils/ad_system_utils.dart';

/// Configuration d'un emplacement publicitaire (ads/open, ads/home_banner,
/// ads/home_banner_referral), telle que lue directement depuis Firestore
/// (lecture publique, voir firestore.rules). Aucun champ ici ne doit jamais
/// etre ecrit par le client -- uniquement par l'Admin ou la Callable
/// recordAdEvent (compteurs).
///
/// Une campagne reservee aux majeurs (`adults_only`) ne publie pas sa
/// creation dans ce document : elle n'est remise par le serveur
/// (getRestrictedAdCreative) qu'a un compte connecte et majeur.
class AdPlacementConfig {
  const AdPlacementConfig({
    required this.enabled,
    required this.imageUrl,
    required this.destinationUrl,
    required this.startAt,
    required this.endAt,
    required this.frequencyCapHours,
    this.campaignId = '',
    this.adultsOnly = false,
    this.communicationType = kAdCommunicationAdvertisement,
    this.displayLabel = '',
  });

  factory AdPlacementConfig.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>?;
    return AdPlacementConfig(
      enabled: data?['enabled'] as bool?,
      imageUrl: (data?['image_url'] as String?)?.trim() ?? '',
      destinationUrl: (data?['destination_url'] as String?)?.trim() ?? '',
      startAt: (data?['start_at'] as Timestamp?)?.toDate(),
      endAt: (data?['end_at'] as Timestamp?)?.toDate(),
      frequencyCapHours: data?['frequency_cap_hours'] as int?,
      campaignId: (data?['campaign_id'] as String?)?.trim() ?? '',
      adultsOnly: data?['adults_only'] == true,
      communicationType:
          normalizeAdCommunicationType(data?['communication_type']),
      displayLabel: (data?['display_label'] as String?) ?? '',
    );
  }

  final bool? enabled;
  final String imageUrl;
  final String destinationUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? frequencyCapHours;
  final String campaignId;
  final bool adultsOnly;
  // advertisement (default) | discovery | proxiplay_info
  final String communicationType;
  // Free label set in the Admin; empty = the type label.
  final String displayLabel;

  String get communicationLabel => adDisplayLabel(
        displayLabel: displayLabel,
        communicationType: communicationType,
      );

  bool get hasUsableCreative => imageUrl.isNotEmpty;

  AdPlacementConfig withCreative({
    required String imageUrl,
    required String destinationUrl,
  }) =>
      AdPlacementConfig(
        enabled: enabled,
        imageUrl: imageUrl,
        destinationUrl: destinationUrl,
        startAt: startAt,
        endAt: endAt,
        frequencyCapHours: frequencyCapHours,
        campaignId: campaignId,
        adultsOnly: adultsOnly,
        communicationType: communicationType,
        displayLabel: displayLabel,
      );
}

class AdSystemService {
  AdSystemService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functionsOverride = functions,
        _firestoreOverride = firestore;

  // Resolved on first use, so a test double never needs a Firebase app.
  final FirebaseFunctions? _functionsOverride;
  final FirebaseFirestore? _firestoreOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'us-central1');
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Future<AdPlacementConfig> getPlacementConfig(String placement) async {
    final snapshot = await _firestore.collection('ads').doc(placement).get();
    return AdPlacementConfig.fromSnapshot(snapshot);
  }

  /// The placement ready to display, creative included. For an adults-only
  /// campaign the creative comes from the server, which only hands it to a
  /// signed-in adult; anyone else gets a config without creative (nothing is
  /// shown). Errors propagate to the caller, which fails open (no ad).
  Future<AdPlacementConfig> getDisplayablePlacement(
    String placement, {
    required bool signedIn,
  }) async {
    final config = await getPlacementConfig(placement);
    if (!config.adultsOnly) return config;
    final restricted = config.withCreative(imageUrl: '', destinationUrl: '');
    if (!signedIn) return restricted;
    final result = await _functions
        .httpsCallable('getRestrictedAdCreative')
        .call({'placement': placement});
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const {};
    if (data['available'] != true || data['campaign_id'] != config.campaignId) {
      return restricted;
    }
    return config.withCreative(
      imageUrl: (data['image_url'] as String?)?.trim() ?? '',
      destinationUrl: (data['destination_url'] as String?)?.trim() ?? '',
    );
  }

  Future<void> recordImpression(String placement, {String campaignId = ''}) =>
      _recordEvent(placement, 'impression', campaignId);

  Future<void> recordClick(String placement, {String campaignId = ''}) =>
      _recordEvent(placement, 'click', campaignId);

  Future<void> _recordEvent(
      String placement, String type, String campaignId) async {
    try {
      await _functions.httpsCallable('recordAdEvent').call({
        'placement': placement,
        'type': type,
        'campaign_id': campaignId,
      });
    } catch (_) {
      // Le tracking ne doit jamais faire echouer/bloquer l'affichage ou la
      // navigation de l'utilisateur : une erreur reseau ici est ignoree.
    }
  }
}
