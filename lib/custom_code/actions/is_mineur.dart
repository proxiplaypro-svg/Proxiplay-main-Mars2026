// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

Future<bool> isMineur(DateTime dateNaissance) async {
  final DateTime today = DateTime.now();
  final int age = today.year - dateNaissance.year;
  final bool isBirthdayPassed = (today.month > dateNaissance.month) ||
      (today.month == dateNaissance.month && today.day >= dateNaissance.day);

  return age < 18 || (age == 18 && !isBirthdayPassed);
}
