import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class EnseignesRecord extends FirestoreRecord {
  EnseignesRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "owner" field.
  DocumentReference? _owner;
  DocumentReference? get owner => _owner;
  bool hasOwner() => _owner != null;

  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "address" field.
  String? _address;
  String get address => _address ?? '';
  bool hasAddress() => _address != null;

  // "city" field.
  String? _city;
  String get city => _city ?? '';
  bool hasCity() => _city != null;

  // "city_insee_code" field.
  String? _cityInseeCode;
  String get cityInseeCode => _cityInseeCode ?? '';
  bool hasCityInseeCode() => _cityInseeCode != null;

  // "area_code" field.
  String? _areaCode;
  String get areaCode => _areaCode ?? '';
  bool hasAreaCode() => _areaCode != null;

  // "phone_number" field.
  String? _phoneNumber;
  String get phoneNumber => _phoneNumber ?? '';
  bool hasPhoneNumber() => _phoneNumber != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "site_web_url" field.
  String? _siteWebUrl;
  String get siteWebUrl => _siteWebUrl ?? '';
  bool hasSiteWebUrl() => _siteWebUrl != null;

  // "instagram_link" field.
  String? _instagramLink;
  String get instagramLink => _instagramLink ?? '';
  bool hasInstagramLink() => _instagramLink != null;

  // "twitter_link" field.
  String? _twitterLink;
  String get twitterLink => _twitterLink ?? '';
  bool hasTwitterLink() => _twitterLink != null;

  // "facebook_link" field.
  String? _facebookLink;
  String get facebookLink => _facebookLink ?? '';
  bool hasFacebookLink() => _facebookLink != null;

  // "category" field.
  List<String>? _category;
  List<String> get category => _category ?? const [];
  bool hasCategory() => _category != null;

  // "google_place_id" field.
  // Association manuelle a une fiche Google (admin uniquement pour l'instant).
  // Aucune autre donnee Google (avis, horaires, photos...) n'est stockee ici.
  String? _googlePlaceId;
  String? get googlePlaceId => _googlePlaceId;
  bool hasGooglePlaceId() => _googlePlaceId != null;

  void _initializeFields() {
    _owner = snapshotData['owner'] as DocumentReference?;
    _createdTime = snapshotData['created_time'] as DateTime?;
    _name = snapshotData['name'] as String?;
    _address = snapshotData['address'] as String?;
    _city = snapshotData['city'] as String?;
    _cityInseeCode = snapshotData['city_insee_code'] as String?;
    _areaCode = snapshotData['area_code'] as String?;
    _phoneNumber = snapshotData['phone_number'] as String?;
    _description = snapshotData['description'] as String?;
    _siteWebUrl = snapshotData['site_web_url'] as String?;
    _instagramLink = snapshotData['instagram_link'] as String?;
    _twitterLink = snapshotData['twitter_link'] as String?;
    _facebookLink = snapshotData['facebook_link'] as String?;
    _category = getDataList(snapshotData['category']);
    _googlePlaceId = snapshotData['google_place_id'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('enseignes');

  static Stream<EnseignesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => EnseignesRecord.fromSnapshot(s));

  static Future<EnseignesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => EnseignesRecord.fromSnapshot(s));

  static EnseignesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      EnseignesRecord._(
        snapshot.reference,
        mapFromFirestore(
          (snapshot.data() as Map<String, dynamic>?) ?? const {},
        ),
      );

  static EnseignesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      EnseignesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'EnseignesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is EnseignesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createEnseignesRecordData({
  DocumentReference? owner,
  DateTime? createdTime,
  String? name,
  String? address,
  String? city,
  String? cityInseeCode,
  String? areaCode,
  String? phoneNumber,
  String? description,
  String? siteWebUrl,
  String? instagramLink,
  String? twitterLink,
  String? facebookLink,
  String? googlePlaceId,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'owner': owner,
      'created_time': createdTime,
      'name': name,
      'address': address,
      'city': city,
      'city_insee_code': cityInseeCode,
      'area_code': areaCode,
      'phone_number': phoneNumber,
      'description': description,
      'site_web_url': siteWebUrl,
      'instagram_link': instagramLink,
      'twitter_link': twitterLink,
      'facebook_link': facebookLink,
      'google_place_id': googlePlaceId,
    }.withoutNulls,
  );

  return firestoreData;
}

class EnseignesRecordDocumentEquality implements Equality<EnseignesRecord> {
  const EnseignesRecordDocumentEquality();

  @override
  bool equals(EnseignesRecord? e1, EnseignesRecord? e2) {
    const listEquality = ListEquality();
    return e1?.owner == e2?.owner &&
        e1?.createdTime == e2?.createdTime &&
        e1?.name == e2?.name &&
        e1?.address == e2?.address &&
        e1?.city == e2?.city &&
        e1?.cityInseeCode == e2?.cityInseeCode &&
        e1?.areaCode == e2?.areaCode &&
        e1?.phoneNumber == e2?.phoneNumber &&
        e1?.description == e2?.description &&
        e1?.siteWebUrl == e2?.siteWebUrl &&
        e1?.instagramLink == e2?.instagramLink &&
        e1?.twitterLink == e2?.twitterLink &&
        e1?.facebookLink == e2?.facebookLink &&
        listEquality.equals(e1?.category, e2?.category) &&
        e1?.googlePlaceId == e2?.googlePlaceId;
  }

  @override
  int hash(EnseignesRecord? e) => const ListEquality().hash([
        e?.owner,
        e?.createdTime,
        e?.name,
        e?.address,
        e?.city,
        e?.cityInseeCode,
        e?.areaCode,
        e?.phoneNumber,
        e?.description,
        e?.siteWebUrl,
        e?.instagramLink,
        e?.twitterLink,
        e?.facebookLink,
        e?.category,
        e?.googlePlaceId,
      ]);

  @override
  bool isValidKey(Object? o) => o is EnseignesRecord;
}

/// Point d'entree pour les futures etapes d'integration Google Places.
/// Ne fait aucun appel a l'API Google -- verifie seulement qu'une
/// association manuelle a ete enregistree.
bool hasGooglePlaceId(EnseignesRecord enseigne) {
  final placeId = enseigne.googlePlaceId;
  return placeId != null && placeId.trim().isNotEmpty;
}
