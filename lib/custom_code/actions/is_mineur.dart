// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

Future<bool> isMineur(DateTime dateNaissance) async {
  final DateTime today = DateTime.now();
  final int age = today.year - dateNaissance.year;
  final bool isBirthdayPassed = (today.month > dateNaissance.month) ||
      (today.month == dateNaissance.month && today.day >= dateNaissance.day);

  return age < 18 || (age == 18 && !isBirthdayPassed);
}
