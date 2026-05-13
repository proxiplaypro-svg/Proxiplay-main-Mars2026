import 'package:collection/collection.dart';

enum Roles {
  commercant,
  joueur,
  admin,
}

enum AccountStatus {
  approved,
  rejected,
  pendingInfo,
  pendingValidation,
  pendingIdentityCard,
  pendingIdentityPhoto,
}

enum ClaimStatus {
  attente,
  recuperer,
}

enum PrizeType {
  principal,
  secondaire,
}

enum ResultGame {
  gagner,
  perdu,
}

enum Category {
  Alimentation,
  Restaurants_bars,
  Beaute_bien_etre,
  Mode,
  Maison_jardin_bricolage,
  Vehicules_mobilite,
  Services_artisans,
  Loisirs_sport_culture,
  Tourisme_evenements,
  Autre_activite_proximite,
}

enum GameType {
  scratcher,
  quiz,
}

enum GameAccessType {
  standard,
  campaign,
  loyalty,
}

enum AccessMode {
  public,
  qr_only,
}

enum DayOfTheWeek {
  Lundi,
  Mardi,
  Mercredi,
  Jeudi,
  Vendredi,
  Samedi,
  Dimanche,
}

extension FFEnumExtensions<T extends Enum> on T {
  String serialize() => name;
}

extension FFEnumListExtensions<T extends Enum> on Iterable<T> {
  T? deserialize(String? value) =>
      firstWhereOrNull((e) => e.serialize() == value);
}

T? deserializeEnum<T>(String? value) {
  switch (T) {
    case (Roles):
      return Roles.values.deserialize(value) as T?;
    case (AccountStatus):
      return AccountStatus.values.deserialize(value) as T?;
    case (ClaimStatus):
      return ClaimStatus.values.deserialize(value) as T?;
    case (PrizeType):
      return PrizeType.values.deserialize(value) as T?;
    case (ResultGame):
      return ResultGame.values.deserialize(value) as T?;
    case (Category):
      return Category.values.deserialize(value) as T?;
    case (GameType):
      return GameType.values.deserialize(value) as T?;
    case (GameAccessType):
      return GameAccessType.values.deserialize(value) as T?;
    case (AccessMode):
      return AccessMode.values.deserialize(value) as T?;
    case (DayOfTheWeek):
      return DayOfTheWeek.values.deserialize(value) as T?;
    default:
      return null;
  }
}
