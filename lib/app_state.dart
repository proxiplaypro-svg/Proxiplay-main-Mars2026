import 'package:flutter/material.dart';
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'dart:convert';

class FFAppState extends ChangeNotifier {
  static FFAppState _instance = FFAppState._internal();

  factory FFAppState() {
    return _instance;
  }

  FFAppState._internal();

  static void reset() {
    _instance = FFAppState._internal();
  }

  Future initializePersistedState() async {
    prefs = await SharedPreferences.getInstance();
    _safeInit(() {
      _isMineur = prefs.getBool('ff_isMineur') ?? _isMineur;
    });
  }

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  late SharedPreferences prefs;

  int _pageIndex = 0;
  int get pageIndex => _pageIndex;
  set pageIndex(int value) {
    _pageIndex = value;
  }

  List<dynamic> _horaires = [jsonDecode('{}')];
  List<dynamic> get horaires => _horaires;
  set horaires(List<dynamic> value) {
    _horaires = value;
  }

  void addToHoraires(dynamic value) {
    horaires.add(value);
  }

  void removeFromHoraires(dynamic value) {
    horaires.remove(value);
  }

  void removeAtIndexFromHoraires(int index) {
    horaires.removeAt(index);
  }

  void updateHorairesAtIndex(
    int index,
    dynamic Function(dynamic) updateFn,
  ) {
    horaires[index] = updateFn(_horaires[index]);
  }

  void insertAtIndexInHoraires(int index, dynamic value) {
    horaires.insert(index, value);
  }

  bool _isMineur = false;
  bool get isMineur => _isMineur;
  set isMineur(bool value) {
    _isMineur = value;
    prefs.setBool('ff_isMineur', value);
  }
}

void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (_) {}
}

Future _safeInitAsync(Function() initializeField) async {
  try {
    await initializeField();
  } catch (_) {}
}
