import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/account_deletion.dart';

class _AuthError implements Exception {
  _AuthError(this.code);
  final String code;
}

String? _code(Object error) => error is _AuthError ? error.code : null;

void main() {
  group('deleteAccountWithReauth', () {
    late int deleteCalls;
    late int reauthCalls;

    setUp(() {
      deleteCalls = 0;
      reauthCalls = 0;
    });

    Future<AccountDeletionOutcome> run({
      bool signedIn = true,
      required List<Object?> deleteResults,
      Object? reauthResult = true,
    }) {
      deleteCalls = 0;
      return deleteAccountWithReauth(
        signedIn: signedIn,
        delete: () async {
          final result = deleteResults[deleteCalls++];
          if (result != null) throw result;
        },
        reauthenticate: () async {
          reauthCalls++;
          if (reauthResult is bool) return reauthResult;
          throw reauthResult!;
        },
        errorCode: _code,
      );
    }

    test('suppression directe confirmee', () async {
      expect(await run(deleteResults: [null]), AccountDeletionOutcome.deleted);
      expect(reauthCalls, 0);
    });

    test('aucun joueur connecte : rien n est tente', () async {
      expect(await run(signedIn: false, deleteResults: []),
          AccountDeletionOutcome.notSignedIn);
      expect(deleteCalls, 0);
    });

    test('connexion trop ancienne : reauthentification puis suppression',
        () async {
      expect(
          await run(deleteResults: [_AuthError('requires-recent-login'), null]),
          AccountDeletionOutcome.deleted);
      expect(reauthCalls, 1);
      expect(deleteCalls, 2);
    });

    test('reauthentification annulee : compte conserve, pas de 2e essai',
        () async {
      expect(
          await run(
              deleteResults: [_AuthError('requires-recent-login')],
              reauthResult: false),
          AccountDeletionOutcome.cancelled);
      expect(deleteCalls, 1);
    });

    test('mot de passe refuse : compte conserve', () async {
      expect(
          await run(
              deleteResults: [_AuthError('requires-recent-login')],
              reauthResult: _AuthError('wrong-password')),
          AccountDeletionOutcome.reauthenticationFailed);
      expect(
          await run(
              deleteResults: [_AuthError('requires-recent-login')],
              reauthResult: _AuthError('invalid-credential')),
          AccountDeletionOutcome.reauthenticationFailed);
    });

    test('reauthentification impossible : parcours de reconnexion', () async {
      expect(
          await run(
              deleteResults: [_AuthError('requires-recent-login')],
              reauthResult: _AuthError('reauth-unsupported')),
          AccountDeletionOutcome.requiresRecentLogin);
      expect(
          await run(
              deleteResults: [_AuthError('requires-recent-login')],
              reauthResult: _AuthError('user-mismatch')),
          AccountDeletionOutcome.requiresRecentLogin);
    });

    test('toujours refusee apres reauthentification', () async {
      expect(
          await run(deleteResults: [
            _AuthError('requires-recent-login'),
            _AuthError('requires-recent-login'),
          ]),
          AccountDeletionOutcome.requiresRecentLogin);
    });

    test('autre erreur (reseau) : echec, jamais presente comme supprime',
        () async {
      expect(await run(deleteResults: [_AuthError('network-request-failed')]),
          AccountDeletionOutcome.failed);
      expect(await run(deleteResults: [StateError('boom')]),
          AccountDeletionOutcome.failed);
      expect(reauthCalls, 0);
    });
  });

  test('mode de reauthentification selon les fournisseurs du compte', () {
    expect(reauthMethodFor(['password']), ReauthMethod.password);
    expect(reauthMethodFor(['google.com']), ReauthMethod.google);
    expect(reauthMethodFor(['apple.com']), ReauthMethod.apple);
    expect(reauthMethodFor(['google.com', 'password']), ReauthMethod.password);
    expect(reauthMethodFor(['phone']), ReauthMethod.unsupported);
    expect(reauthMethodFor(const []), ReauthMethod.unsupported);
  });

  test('messages en francais, explicites sur le compte conserve', () {
    for (final message in [
      kAccountDeletionCancelledMessage,
      kAccountDeletionFailedMessage,
      kRecentLoginRequiredMessage,
      kReauthWrongPasswordMessage,
    ]) {
      expect(message, contains('n’a pas été supprimé'));
    }
  });

  // The page depends on Firebase: its wiring is guarded from the source text.
  test('le profil ne renvoie vers la connexion qu apres suppression confirmee',
      () {
    final page = File(
            'lib/pages/joueur/profil_joueur_page/profil_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final managerSource =
        File('lib/auth/firebase_auth/firebase_auth_manager.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
    // Only the deletion method: updateEmail keeps its own message.
    final deleteStart =
        managerSource.indexOf('deleteUser(BuildContext context)');
    final manager = managerSource.substring(
        deleteStart, managerSource.indexOf('Future updateEmail', deleteStart));
    expect(page,
        contains('final outcome = await authManager.deleteUser(context);'));
    expect(page, contains('_handleAccountDeletionOutcome(outcome, messenger)'));
    expect(
        page,
        isNot(contains(
            'await authManager.deleteUser(context);\n      if (!context.mounted) return;\n      context.pushNamed(LoginPageWidget.routeName);')));
    // Login only after a confirmed deletion or a chosen reconnection.
    expect('context.goNamed(LoginPageWidget.routeName)'.allMatches(page).length,
        2);
    expect(page, isNot(contains('pushNamed(LoginPageWidget.routeName)')));
    expect(page, contains('case AccountDeletionOutcome.requiresRecentLogin:'));
    expect(manager, isNot(contains('Too long since most recent sign in')));
    expect(manager, contains('deleteAccountWithReauth('));
  });
}
