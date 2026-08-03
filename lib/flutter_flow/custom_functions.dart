import 'dart:math' as math;

import '/backend/schema/enums/enums.dart';
import '/utils/minor_restricted_game_access.dart'
    as minor_restricted_game_access;

DayOfTheWeek stringDayIntoEnumDay(String day) {
  // convert string in enum item
  switch (day) {
    case 'Lundi':
      return DayOfTheWeek.Lundi;
    case 'Mardi':
      return DayOfTheWeek.Mardi;
    case 'Mercredi':
      return DayOfTheWeek.Mercredi;
    case 'Jeudi':
      return DayOfTheWeek.Jeudi;
    case 'Vendredi':
      return DayOfTheWeek.Vendredi;
    case 'Samedi':
      return DayOfTheWeek.Samedi;
    case 'Dimanche':
      return DayOfTheWeek.Dimanche;
    default:
      throw Exception('Invalid day string: $day');
  }
}

List<DayOfTheWeek>? filterDayWeek(
  List<DayOfTheWeek> daySelected,
  List<DayOfTheWeek> dayOfTheWeek,
) {
  // j'ai une enumération de jours (dayoftheweek) et je veux retourner cette liste avec les valeurs en moins de la liste (daySelected)
  return dayOfTheWeek.where((day) => !daySelected.contains(day)).toList();
}

List<int> randomLots(int nombreLots) {
  Set<int> uniqueNumbers = {};
  var rng = math.Random(); // Une seule instance de Random
  var winMaxRange = 50 * nombreLots;

  while (uniqueNumbers.length < nombreLots) {
    uniqueNumbers.add(rng.nextInt(winMaxRange) + 1);
  }

  return uniqueNumbers.toList();
}

bool checkValueIsEmpty(String value) {
  // retourne un boolean si la value est vide
  return value.isEmpty;
}

int textToNumber(String textValue) {
  // Trim any leading or trailing whitespace
  textValue = textValue.trim();

  // Try to parse the string to an integer
  try {
    // Convert the string to an integer
    return int.parse(textValue);
  } catch (e) {
    // If parsing fails, return 0
    return 0;
  }
}

bool isAdult(DateTime date) => minor_restricted_game_access.isAdult(date);

DateTime addDate(int heure) {
  // retourner une date précise en fonction de l'heure passer en arguments (integer)
  DateTime now = DateTime.now();
  DateTime newDate = DateTime(now.year, now.month, now.day, heure);
  return newDate;
}
