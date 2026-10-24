import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/push_notifications/fcm_device_detach.dart';

// Detaching this device from an account at sign-out (24/10/2026 Samsung
// finding: a push meant for the previous account - the inviter - showed up
// during another account's signup on the same phone).
class _Device {
  _Device({this.token = 'T1'});
  String? token;
  final calls = <String>[];
  final deletedDocs = <String>[];
  String? pending;
  bool offline = false;
  bool hang = false;

  Future<void> _net() async {
    if (hang) await Completer<void>().future;
    if (offline) throw Exception('UNAVAILABLE');
  }

  FcmDetachDeps get deps => FcmDetachDeps(
        readToken: () async {
          calls.add('read');
          return token;
        },
        deleteTokenDoc: (path, t) async {
          calls.add('deleteDoc');
          await _net();
          deletedDocs.add('$path/fcm_tokens/$t');
        },
        invalidateToken: () async {
          calls.add('invalidate');
          await _net();
          token = null;
        },
        savePending: (value) async {
          calls.add('savePending');
          pending = value;
        },
        clearPending: () async {
          calls.add('clearPending');
          pending = null;
        },
      );
}

const _short = Duration(milliseconds: 50);

void main() {
  group('detachDeviceFromAccount (sign-out)', () {
    test('deletes only this device token document, then invalidates the token', () async {
      final device = _Device();
      final result = await detachDeviceFromAccount(userPath: 'users/A', deps: device.deps);
      expect(device.calls, ['read', 'savePending', 'deleteDoc', 'invalidate', 'clearPending']);
      // Other devices of the same account keep their own documents.
      expect(device.deletedDocs, ['users/A/fcm_tokens/T1']);
      expect(device.token, isNull);
      expect(device.pending, isNull);
      expect(result.complete, isTrue);
    });

    test('offline: never throws, and the detach stays pending for the next start', () async {
      final device = _Device()..offline = true;
      final result = await detachDeviceFromAccount(userPath: 'users/A', deps: device.deps, timeout: _short);
      expect(result.docDeleted, isFalse);
      expect(result.complete, isFalse);
      expect(jsonDecode(device.pending!), {'path': 'users/A', 'token': 'T1'});
    });

    test('a step that hangs is abandoned after the timeout, the sign-out goes on', () async {
      final device = _Device()..hang = true;
      final watch = Stopwatch()..start();
      final result = await detachDeviceFromAccount(userPath: 'users/A', deps: device.deps, timeout: _short);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(result.complete, isFalse);
      expect(device.pending, isNotNull);
    });

    test('no token on the device (notifications refused): nothing to delete, still invalidated', () async {
      final device = _Device(token: null);
      final result = await detachDeviceFromAccount(userPath: 'users/A', deps: device.deps);
      expect(device.deletedDocs, isEmpty);
      expect(device.calls, contains('invalidate'));
      expect(device.pending, isNull);
      expect(result.complete, isTrue);
    });
  });

  group('retryPendingFcmDetach (app start after an incomplete sign-out)', () {
    String pendingOf(String path, String token) => jsonEncode({'path': path, 'token': token});

    test('signed out since: the token is invalidated, the other account document is not touched', () async {
      final device = _Device()..pending = pendingOf('users/A', 'T1');
      expect(await retryPendingFcmDetach(pending: device.pending, currentUid: null, deps: device.deps), isTrue);
      expect(device.deletedDocs, isEmpty, reason: 'only the owner may delete it; the server drops dead tokens');
      expect(device.token, isNull);
      expect(device.pending, isNull);
    });

    test('same account signed in again: its stale document is deleted too', () async {
      final device = _Device()..pending = pendingOf('users/A', 'T1');
      await retryPendingFcmDetach(pending: device.pending, currentUid: 'A', deps: device.deps);
      expect(device.deletedDocs, ['users/A/fcm_tokens/T1']);
      expect(device.token, isNull);
    });

    test('token already renewed: nothing to invalidate, the new token is kept', () async {
      final device = _Device(token: 'T2')..pending = pendingOf('users/A', 'T1');
      expect(await retryPendingFcmDetach(pending: device.pending, currentUid: 'B', deps: device.deps), isTrue);
      expect(device.calls, isNot(contains('invalidate')));
      expect(device.token, 'T2');
      expect(device.pending, isNull);
    });

    test('still offline: kept pending; unreadable marker: discarded; nothing pending: no-op', () async {
      final offline = _Device()..offline = true..pending = pendingOf('users/A', 'T1');
      expect(await retryPendingFcmDetach(pending: offline.pending, currentUid: null, deps: offline.deps, timeout: _short), isFalse);
      expect(offline.pending, isNotNull);
      final corrupt = _Device()..pending = '{not json';
      expect(await retryPendingFcmDetach(pending: corrupt.pending, currentUid: null, deps: corrupt.deps), isFalse);
      expect(corrupt.pending, isNull);
      final idle = _Device();
      expect(await retryPendingFcmDetach(pending: null, currentUid: 'A', deps: idle.deps), isFalse);
      expect(idle.calls, isEmpty);
    });
  });

  group('shouldRegisterFcmToken', () {
    test('only for the signed-in account, never during a sign-out', () {
      expect(shouldRegisterFcmToken(userPath: 'users/A', currentUid: 'A', suspended: false), isTrue);
      expect(shouldRegisterFcmToken(userPath: 'users/A', currentUid: 'A', suspended: true), isFalse);
      expect(shouldRegisterFcmToken(userPath: 'users/A', currentUid: 'B', suspended: false), isFalse,
          reason: 'a late refresh of the previous account is never registered');
      expect(shouldRegisterFcmToken(userPath: 'users/A', currentUid: null, suspended: false), isFalse);
    });
  });

  group('wiring', () {
    String source(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('signOut detaches the device before the Firebase sign-out, and always signs out', () {
      final manager = source('lib/auth/firebase_auth/firebase_auth_manager.dart');
      final body = manager.substring(manager.indexOf('Future signOut() async {'));
      final suspend = body.indexOf('fcmRegistrationSuspended = true;');
      final detach = body.indexOf('await detachDeviceFromAccount(');
      final signOut = body.indexOf('return await FirebaseAuth.instance.signOut();');
      final resume = body.indexOf('} finally {\n      fcmRegistrationSuspended = false;');
      expect([suspend, detach, signOut, resume].every((i) => i >= 0), isTrue);
      expect(suspend < detach && detach < signOut && signOut < resume, isTrue);
    });

    test('every sign-out button goes through authManager.signOut()', () {
      final direct = Directory('lib/pages').listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('FirebaseAuth.instance.signOut()'));
      expect(direct, isEmpty);
    });

    test('the token stream stops at sign-out and checks the signed-in account', () {
      final util = source('lib/backend/push_notifications/push_notifications_util.dart');
      expect(util, isNot(contains('.where((user) => user != null)')));
      expect(util, contains('? Stream<UserTokenInfo>.empty()'));
      expect(util, contains('suspended: fcmRegistrationSuspended,'));
    });

    test('an incomplete detach is finished at start, before any token registration', () {
      final main = source('lib/main.dart');
      final retry = main.indexOf('retryPendingFcmDetachOnStart().whenComplete(');
      expect(retry, greaterThan(0));
      expect(main.indexOf('_fcmTokenSub = fcmTokenUserStream.listen', retry), greaterThan(retry));
    });
  });
}
