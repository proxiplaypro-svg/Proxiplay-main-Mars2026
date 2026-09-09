import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/schema/prizes_record.dart';
import 'package:proxi_play/backend/schema/enseignes_record.dart';

// Only path access is needed for these schema contract tests.
// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.path);
  @override
  final String path;
  @override
  FirebaseFirestore get firestore => _Firestore();
}

// ignore: subtype_of_sealed_class
class _Firestore extends Fake implements FirebaseFirestore {
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) => _Reference(path);
}

void main() {
  PrizesRecord prize(Map<String, dynamic> data) =>
      PrizesRecord.getDocumentFromData(data, _Reference('prizes/local_test'));
  final owner = _Reference('users/merchant');
  final shop = _Reference('enseignes/shop');

  test('admin owner reference and historical strings remain readable by Flutter', () {
    for (final raw in [owner, 'merchant', 'users/merchant', '/users/merchant']) {
      final record = EnseignesRecord.getDocumentFromData({'owner': raw}, shop);
      expect(record.owner?.path, 'users/merchant');
    }
    expect(EnseignesRecord.getDocumentFromData({'owner': '/shops/invalid'}, shop).owner, isNull);
  });

  test('claim checks owner priority, beneficiary, expiry and platform routing',
      () {
    final data = <String, dynamic>{
      'owner_id': owner,
      'enseigne_id': shop,
      'winner_id': _Reference('users/winner'),
      'claimed': false
    };
    expect(prize(data).canBeClaimedBy('merchant', {}), true);
    expect(prize(data).canBeClaimedBy('other', {'enseignes/shop'}), false);
    expect(
        prize(data)
            .canBeClaimedBy('merchant', {}, expectedWinnerPath: 'users/other'),
        false);
    expect(
        prize({...data, 'usage_deadline': DateTime(2000)})
            .canBeClaimedBy('merchant', {}),
        false);
    expect(prize({...data, 'claimed': true}).canBeClaimedBy('merchant', {}),
        false);
    for (final type in ['platform', 'partner', 'review']) {
      expect(
          prize({...data, 'fulfillment_type': type})
              .canBeClaimedBy('merchant', {}),
          false);
    }
    expect(
        prize({...data, 'prize_type': 'animation'})
            .canBeClaimedBy('merchant', {}),
        false);
    expect(prize({}).canBeClaimedBy('merchant', {'enseignes/shop'}), false);
  });

  test(
      'modern and legacy with both routing references keep merchant validation',
      () {
    for (final type in [null, 'merchant']) {
      final lot = prize({
        'owner_id': owner,
        'enseigne_id': shop,
        if (type != null) 'fulfillment_type': type,
        'claimed': false
      });
      expect(lot.isAvailable, true);
      expect(lot.fulfillmentType, 'merchant');
    }
  });

  test(
      'historical prizes with either trusted routing reference remain claimable',
      () {
    for (final data in [
      {'owner_id': owner},
      {'enseigne_id': shop}
    ]) {
      final lot = prize({...data, 'claimed': false});
      expect(lot.isAvailable, true);
      expect(lot.fulfillmentType, 'merchant');
      expect(lot.canBeClaimedBy('merchant', {'enseignes/shop'}), true);
      expect(lot.canBeClaimedBy('other', {}), false);
    }
  });

  test('platform and expired/used prizes cannot use merchant validation button',
      () {
    final platform = prize(
        {'prize_type': 'animation', 'owner_id': owner, 'enseigne_id': shop});
    expect(platform.fulfillmentType, 'platform');
    expect(prize({'claimed': true}).isAvailable, false);
    expect(prize({'usage_deadline': DateTime(2000)}).isAvailable, false);
  });
}
