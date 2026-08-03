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
      _globalTickerTotalPlayers =
          prefs.getInt('ff_globalTickerTotalPlayers') ??
              _globalTickerTotalPlayers;
      _globalTickerTotalGamesPlayed =
          prefs.getInt('ff_globalTickerTotalGamesPlayed') ??
              _globalTickerTotalGamesPlayed;
      _globalTickerTotalMerchants =
          prefs.getInt('ff_globalTickerTotalMerchants') ??
              _globalTickerTotalMerchants;
      _globalTickerMessages =
          prefs.getStringList('ff_globalTickerMessages') ??
              _globalTickerMessages;
      final updatedAtMillis = prefs.getInt('ff_globalTickerUpdatedAtMillis');
      _globalTickerUpdatedAt = updatedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtMillis)
          : _globalTickerUpdatedAt;
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

  bool _offerProfileCompletionAfterLogin = false;
  bool get offerProfileCompletionAfterLogin => _offerProfileCompletionAfterLogin;
  set offerProfileCompletionAfterLogin(bool value) {
    _offerProfileCompletionAfterLogin = value;
  }

  String _profileCompletionReturnRouteName = '';
  String get profileCompletionReturnRouteName => _profileCompletionReturnRouteName;
  set profileCompletionReturnRouteName(String value) {
    _profileCompletionReturnRouteName = value.trim();
  }

  bool get hasProfileCompletionReturnRouteName =>
      _profileCompletionReturnRouteName.isNotEmpty;

  void clearProfileCompletionPromptState() {
    _offerProfileCompletionAfterLogin = false;
    _profileCompletionReturnRouteName = '';
  }

  int _globalTickerTotalPlayers = 0;
  int get globalTickerTotalPlayers => _globalTickerTotalPlayers;
  set globalTickerTotalPlayers(int value) {
    _globalTickerTotalPlayers = value;
    if (_prefsReady) {
      prefs.setInt('ff_globalTickerTotalPlayers', value);
    }
  }

  int _globalTickerTotalGamesPlayed = 0;
  int get globalTickerTotalGamesPlayed => _globalTickerTotalGamesPlayed;
  set globalTickerTotalGamesPlayed(int value) {
    _globalTickerTotalGamesPlayed = value;
    if (_prefsReady) {
      prefs.setInt('ff_globalTickerTotalGamesPlayed', value);
    }
  }

  int _globalTickerTotalMerchants = 0;
  int get globalTickerTotalMerchants => _globalTickerTotalMerchants;
  set globalTickerTotalMerchants(int value) {
    _globalTickerTotalMerchants = value;
    if (_prefsReady) {
      prefs.setInt('ff_globalTickerTotalMerchants', value);
    }
  }

  List<String> _globalTickerMessages = const <String>[];
  List<String> get globalTickerMessages => _globalTickerMessages;
  set globalTickerMessages(List<String> value) {
    _globalTickerMessages = List<String>.from(value);
    if (_prefsReady) {
      prefs.setStringList('ff_globalTickerMessages', _globalTickerMessages);
    }
  }

  DateTime? _globalTickerUpdatedAt;
  DateTime? get globalTickerUpdatedAt => _globalTickerUpdatedAt;
  set globalTickerUpdatedAt(DateTime? value) {
    _globalTickerUpdatedAt = value;
    if (_prefsReady) {
      if (value == null) {
        prefs.remove('ff_globalTickerUpdatedAtMillis');
      } else {
        prefs.setInt('ff_globalTickerUpdatedAtMillis', value.millisecondsSinceEpoch);
      }
    }
  }

  void setGlobalTickerData({
    required int totalPlayers,
    required int totalGamesPlayed,
    required int totalMerchants,
    required List<String> messages,
    DateTime? updatedAt,
  }) {
    _globalTickerTotalPlayers = totalPlayers;
    _globalTickerTotalGamesPlayed = totalGamesPlayed;
    _globalTickerTotalMerchants = totalMerchants;
    _globalTickerMessages = List<String>.from(messages);
    _globalTickerUpdatedAt = updatedAt;

    if (_prefsReady) {
      prefs.setInt('ff_globalTickerTotalPlayers', _globalTickerTotalPlayers);
      prefs.setInt(
          'ff_globalTickerTotalGamesPlayed', _globalTickerTotalGamesPlayed);
      prefs.setInt('ff_globalTickerTotalMerchants', _globalTickerTotalMerchants);
      prefs.setStringList('ff_globalTickerMessages', _globalTickerMessages);
      if (_globalTickerUpdatedAt == null) {
        prefs.remove('ff_globalTickerUpdatedAtMillis');
      } else {
        prefs.setInt(
          'ff_globalTickerUpdatedAtMillis',
          _globalTickerUpdatedAt!.millisecondsSinceEpoch,
        );
      }
    }
  }
}

void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (_) {}
}
