import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

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
    _prefsReady = true;
    _safeInit(() {
      _isMineur = prefs.getBool('ff_isMineur') ?? _isMineur;
      _isGuest = prefs.getBool('ff_isGuest') ?? _isGuest;
      _pendingDeepLinkGameId =
          prefs.getString('ff_pendingDeepLinkGameId') ?? _pendingDeepLinkGameId;
      _pendingReferralCode =
          prefs.getString('ff_pendingReferralCode') ?? _pendingReferralCode;
      debugPrint(
        '[ReferralDebug][AppState] initialized pendingReferralCode='
        '${_pendingReferralCode.isEmpty ? '<empty>' : _pendingReferralCode}',
      );
    });
  }

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  late SharedPreferences prefs;
  bool _prefsReady = false;

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
    if (_prefsReady) {
      prefs.setBool('ff_isMineur', value);
    }
  }

  // Non-persisted: used to avoid UI "flash" during logout navigation.
  bool _isLoggingOut = false;
  bool get isLoggingOut => _isLoggingOut;
  set isLoggingOut(bool value) {
    _isLoggingOut = value;
  }

  bool _isGuest = false;
  bool get isGuest => _isGuest;
  set isGuest(bool value) {
    _isGuest = value;
    if (_prefsReady) {
      prefs.setBool('ff_isGuest', value);
    }
  }

  String _pendingDeepLinkGameId = '';
  String get pendingDeepLinkGameId => _pendingDeepLinkGameId;
  set pendingDeepLinkGameId(String value) {
    _pendingDeepLinkGameId = value.trim();
    if (_prefsReady) {
      if (_pendingDeepLinkGameId.isEmpty) {
        prefs.remove('ff_pendingDeepLinkGameId');
      } else {
        prefs.setString('ff_pendingDeepLinkGameId', _pendingDeepLinkGameId);
      }
    }
  }

  bool get hasPendingDeepLinkGameId => _pendingDeepLinkGameId.isNotEmpty;

  void clearPendingDeepLinkGameId() {
    _pendingDeepLinkGameId = '';
    if (_prefsReady) {
      prefs.remove('ff_pendingDeepLinkGameId');
    }
  }

  String _pendingReferralCode = '';
  String get pendingReferralCode => _pendingReferralCode;
  set pendingReferralCode(String value) {
    _pendingReferralCode = value.trim().toUpperCase();
    debugPrint(
      '[ReferralDebug][AppState] saving pendingReferralCode='
      '${_pendingReferralCode.isEmpty ? '<empty>' : _pendingReferralCode}',
    );
    if (_prefsReady) {
      prefs.setString('ff_pendingReferralCode', _pendingReferralCode);
    }
  }

  bool get hasPendingReferralCode => _pendingReferralCode.isNotEmpty;

  void clearPendingReferralCode() {
    debugPrint(
      '[ReferralDebug][AppState] clearing pendingReferralCode='
      '${_pendingReferralCode.isEmpty ? '<empty>' : _pendingReferralCode}',
    );
    _pendingReferralCode = '';
    if (_prefsReady) {
      prefs.remove('ff_pendingReferralCode');
    }
  }
}

void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (_) {}
}
