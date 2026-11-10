/// Conditions du programme de parrainage commercant (1.1.4), lues dans
/// `app_config/merchant_referral.conditions` pour pouvoir les modifier sans
/// nouvelle version de l'app. Publication cote serveur seulement
/// (firebase/functions/merchant_referral_conditions.js, meme format).
///
/// Format "plain_v1" : paragraphes separes par une ligne vide, une ligne
/// commencant par "- " est un element de liste.
///
/// La source affichee est toujours explicite : jamais une copie locale
/// presentee comme la version a jour.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

const String kMerchantReferralConditionsFormat = 'plain_v1';

/// Copie integree a l'app (version 1 validee le 10/11/2026), affichee
/// seulement en secours et toujours signalee comme telle. Identique a
/// firebase/functions/merchant_referral_conditions_v1.txt (test croise).
const String kEmbeddedMerchantReferralConditionsTitle =
    'Conditions du programme de parrainage commerçant';
const String kEmbeddedMerchantReferralConditionsText =
    "Le programme de parrainage ProxiPlay est ouvert aux joueurs et aux commerçants disposant d'un compte ProxiPlay.\n"
    '\n'
    'Le parrain reçoit 50 € en bons cadeaux utilisables chez les commerçants partenaires de ProxiPlay, sous réserve des conditions suivantes :\n'
    '\n'
    '- Le commerçant parrainé doit être un nouveau client ProxiPlay.\n'
    '- Il doit renseigner le code de parrainage lors de la création de son compte.\n'
    '- Il doit avoir souscrit et intégralement réglé son premier abonnement ProxiPlay.\n'
    "- Le paiement doit être confirmé et ne pas avoir fait l'objet d'une annulation ou d'un remboursement.\n"
    "- Un commerçant ne peut être parrainé qu'une seule fois.\n"
    '- Un commerçant ne peut pas se parrainer lui-même.\n'
    '\n'
    'La récompense est attribuée après vérification et validation du parrainage par ProxiPlay.\n'
    '\n'
    'Les bons cadeaux sont exclusivement utilisables chez les commerçants partenaires ProxiPlay participant au programme. Ils ne sont ni échangeables contre des espèces ni remboursables.\n'
    '\n'
    'ProxiPlay peut refuser ou annuler tout parrainage frauduleux, fictif ou ne respectant pas les présentes conditions.\n'
    '\n'
    'Les parrainages antérieurs restent soumis aux conditions applicables lors de leur enregistrement.';

const String kConditionsCacheNotice =
    'Connexion impossible : voici la dernière version enregistrée sur cet '
    'appareil. Elle a pu être modifiée depuis.';
const String kConditionsEmbeddedNotice =
    'Les conditions en ligne n’ont pas pu être chargées. Voici la version '
    'intégrée à l’application, qui peut ne pas être la plus récente.';

sealed class ConditionsBlock {
  const ConditionsBlock();
}

class ConditionsParagraph extends ConditionsBlock {
  const ConditionsParagraph(this.text);
  final String text;
}

class ConditionsList extends ConditionsBlock {
  const ConditionsList(this.items);
  final List<String> items;
}

/// Meme decoupage que parseConditionsText cote serveur.
List<ConditionsBlock> parseMerchantReferralConditionsText(String text) {
  final normalized = text
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
      .trim();
  final blocks = <ConditionsBlock>[];
  for (final chunk in normalized.split(RegExp(r'\n\s*\n'))) {
    final lines = chunk
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    var paragraph = <String>[];
    var items = <String>[];
    void flushParagraph() {
      if (paragraph.isNotEmpty) blocks.add(ConditionsParagraph(paragraph.join(' ')));
      paragraph = [];
    }

    void flushList() {
      if (items.isNotEmpty) blocks.add(ConditionsList(items));
      items = [];
    }

    for (final line in lines) {
      if (line.startsWith('- ')) {
        flushParagraph();
        items.add(line.substring(2).trim());
      } else {
        flushList();
        paragraph.add(line);
      }
    }
    flushParagraph();
    flushList();
  }
  return blocks;
}

class MerchantReferralConditions {
  const MerchantReferralConditions({
    required this.title,
    required this.blocks,
    this.version,
    this.effectiveAt,
    this.updatedAt,
  });

  final String title;
  final List<ConditionsBlock> blocks;

  /// null pour la copie integree.
  final int? version;
  final DateTime? effectiveAt;
  final DateTime? updatedAt;

  static MerchantReferralConditions get embedded => MerchantReferralConditions(
        title: kEmbeddedMerchantReferralConditionsTitle,
        blocks: parseMerchantReferralConditionsText(
            kEmbeddedMerchantReferralConditionsText),
      );

  /// Conditions publiees dans le document de configuration, ou null si
  /// elles sont absentes ou invalides (format inconnu, champ manquant).
  static MerchantReferralConditions? fromConfig(Map<String, dynamic>? config) {
    final raw = config?['conditions'];
    if (raw is! Map) return null;
    final version = raw['version'];
    final title = raw['title'];
    final text = raw['text'];
    if (version is! int || version < 1 ||
        raw['format'] != kMerchantReferralConditionsFormat ||
        title is! String || title.trim().isEmpty ||
        text is! String) {
      return null;
    }
    final blocks = parseMerchantReferralConditionsText(text);
    if (blocks.isEmpty) return null;
    DateTime? date(Object? value) => value is Timestamp ? value.toDate() : null;
    return MerchantReferralConditions(
      title: title.trim(),
      blocks: blocks,
      version: version,
      effectiveAt: date(raw['effective_at']),
      updatedAt: date(raw['updated_at']),
    );
  }
}

enum MerchantReferralConditionsSource {
  /// Lue sur le serveur a l'instant.
  online,

  /// Derniere version publiee enregistree sur l'appareil (hors connexion).
  deviceCache,

  /// Copie integree a l'app : rien d'exploitable en ligne ni en cache.
  embedded,
}

class MerchantReferralConditionsResult {
  const MerchantReferralConditionsResult(this.conditions, this.source);
  final MerchantReferralConditions conditions;
  final MerchantReferralConditionsSource source;

  /// Message a afficher au-dessus des conditions, null pour la version en ligne.
  String? get notice => switch (source) {
        MerchantReferralConditionsSource.online => null,
        MerchantReferralConditionsSource.deviceCache => kConditionsCacheNotice,
        MerchantReferralConditionsSource.embedded => kConditionsEmbeddedNotice,
      };
}

/// Choix de la source a partir d'une lecture du document de configuration.
MerchantReferralConditionsResult resolveMerchantReferralConditions({
  Map<String, dynamic>? config,
  required bool fromCache,
}) {
  final parsed = MerchantReferralConditions.fromConfig(config);
  if (parsed == null) {
    return MerchantReferralConditionsResult(
        MerchantReferralConditions.embedded,
        MerchantReferralConditionsSource.embedded);
  }
  return MerchantReferralConditionsResult(
    parsed,
    fromCache
        ? MerchantReferralConditionsSource.deviceCache
        : MerchantReferralConditionsSource.online,
  );
}

/// Lecture a chaque ouverture (jamais de copie memorisee par l'app) :
/// serveur d'abord, puis cache de l'appareil, puis copie integree.
Future<MerchantReferralConditionsResult> loadMerchantReferralConditions({
  FirebaseFirestore? firestore,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final ref = (firestore ?? FirebaseFirestore.instance)
      .doc('app_config/merchant_referral');
  try {
    final snapshot = await ref.get().timeout(timeout);
    return resolveMerchantReferralConditions(
      config: snapshot.data(),
      fromCache: snapshot.metadata.isFromCache,
    );
  } catch (_) {
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      return resolveMerchantReferralConditions(
          config: cached.data(), fromCache: true);
    } catch (_) {
      return resolveMerchantReferralConditions(config: null, fromCache: true);
    }
  }
}

String formatConditionsDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// « Version 2 · en vigueur depuis le 10/11/2026 », vide pour la copie
/// integree.
String conditionsVersionLabel(MerchantReferralConditions conditions) {
  final version = conditions.version;
  if (version == null) return '';
  final effective = conditions.effectiveAt;
  return effective == null
      ? 'Version $version'
      : 'Version $version · en vigueur depuis le ${formatConditionsDate(effective)}';
}
