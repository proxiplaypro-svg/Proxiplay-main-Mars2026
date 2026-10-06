import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Configuration d'un emplacement publicitaire (ads/open ou
/// ads/home_banner), telle que lue directement depuis Firestore (lecture
/// publique, voir firestore.rules). Aucun champ ici ne doit jamais etre
/// ecrit par le client -- uniquement par l'Admin ou la Callable
/// recordAdEvent (compteurs).
class AdPlacementConfig {
  const AdPlacementConfig({
    required this.enabled,
    required this.imageUrl,
    required this.destinationUrl,
    required this.startAt,
    required this.endAt,
    required this.frequencyCapHours,
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
    );
  }

  final bool? enabled;
  final String imageUrl;
  final String destinationUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? frequencyCapHours;

  bool get hasUsableCreative => imageUrl.isNotEmpty;
}

class AdSystemService {
  AdSystemService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  Future<AdPlacementConfig> getPlacementConfig(String placement) async {
    final snapshot =
        await _firestore.collection('ads').doc(placement).get();
    return AdPlacementConfig.fromSnapshot(snapshot);
  }

  Future<void> recordImpression(String placement) =>
      _recordEvent(placement, 'impression');

  Future<void> recordClick(String placement) =>
      _recordEvent(placement, 'click');

  Future<void> _recordEvent(String placement, String type) async {
    try {
      await _functions.httpsCallable('recordAdEvent').call({
        'placement': placement,
        'type': type,
      });
    } catch (_) {
      // Le tracking ne doit jamais faire echouer/bloquer l'affichage ou la
      // navigation de l'utilisateur : une erreur reseau ici est ignoree.
    }
  }
}
