import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/referral_invite_flow.dart';
import 'package:share_plus/share_plus.dart';

// "Inviter un ami" (26/10/2026 report): which step failed, no new
// invitation per retry, and a copyable link when the share sheet fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 0, 18);
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  late UnsentReferralInvites store;
  late int created;
  late List<ReferralInviteFailure> reported;
  setUp(() {
    store = UnsentReferralInvites();
    created = 0;
    reported = [];
  });

  Future<Map<String, dynamic>> createReferral() async {
    created++;
    final code = 'ABCDEF0$created';
    return {'inviteCode': code, 'shareLink': 'https://play.proxiplay.fr/i?ref=$code'};
  }

  PreparedReferralInvite build(Map<String, dynamic> response, DateTime at) {
    final code = response['inviteCode'] as String;
    final link = 'https://play.proxiplay.fr/i?ref=$code';
    return PreparedReferralInvite(code: code, link: link, text: 'Rejoins-moi $link', createdAt: at);
  }

  Future<ReferralInviteOutcome> tap(
    Future<ShareResultStatus> Function(String text) share, {
    String account = 'player',
    DateTime? at,
    Future<Map<String, dynamic>> Function()? create,
    PreparedReferralInvite Function(Map<String, dynamic>, DateTime)? buildInvite,
  }) =>
      runReferralInvite(
        accountId: account,
        createReferral: create ?? createReferral,
        buildInvite: buildInvite ?? build,
        share: share,
        now: at ?? now,
        store: store,
        onFailure: reported.add,
      );

  Future<ShareResultStatus> shared(String _) async => ShareResultStatus.success;
  Future<ShareResultStatus> failing(String _) async =>
      throw PlatformException(code: 'Share failed', message: 'No Activity found to handle Intent');

  test('success: one invitation, shared, and the next tap creates a new one', () async {
    final first = await tap(shared);
    expect(first.status, ReferralInviteStatus.shared);
    expect(created, 1);
    await tap(shared);
    expect(created, 2, reason: 'a shared code is single-use: never reused');
    expect(reported, isEmpty);
  });

  test('share sheet failure: link copyable, and retries reuse the same invitation', () async {
    final first = await tap(failing);
    expect(first.status, ReferralInviteStatus.failed);
    expect(first.canCopyLink, isTrue);
    expect(first.invite!.link, 'https://play.proxiplay.fr/i?ref=ABCDEF01');
    expect(first.failure!.stage, ReferralInviteStage.openShare);
    expect(first.failure!.errorType, 'PlatformException');
    expect(first.failure!.errorCode, 'Share failed');
    for (var i = 0; i < 5; i++) {
      final again = await tap(failing);
      expect(again.reused, isTrue);
      expect(again.invite!.code, 'ABCDEF01');
    }
    expect(created, 1, reason: 'six failed taps, one invitation');
    final ok = await tap(shared);
    expect(ok.status, ReferralInviteStatus.shared);
    expect(ok.invite!.code, 'ABCDEF01', reason: 'the unsent invitation is the one finally shared');
    expect(created, 1);
  });

  test('a copied link is never reused for another friend', () async {
    await tap(failing);
    store.handedOver('player'); // what "Copier le lien" does
    await tap(shared);
    expect(created, 2);
  });

  test('closing the share sheet keeps the invitation; an unknown result does not', () async {
    await tap((_) async => ShareResultStatus.dismissed);
    await tap((_) async => ShareResultStatus.unavailable);
    expect(created, 1, reason: 'dismissed: reused');
    final next = await tap(shared);
    expect(next.reused, isFalse, reason: 'unavailable: possibly sent');
    expect(created, 2);
  });

  test('an unsent invitation is per account and expires after an hour', () async {
    await tap(failing, account: 'a');
    await tap(failing, account: 'b');
    expect(created, 2);
    await tap(failing, account: 'a', at: now.add(const Duration(minutes: 59)));
    expect(created, 2);
    await tap(failing, account: 'a', at: now.add(const Duration(minutes: 61)));
    expect(created, 3);
  });

  test('createReferral failure: reported with its code, nothing to copy', () async {
    final outcome = await tap(shared,
        create: () async => throw FirebaseFunctionsException(
            code: 'failed-precondition', message: 'No active share campaign is available.'));
    expect(outcome.status, ReferralInviteStatus.failed);
    expect(outcome.canCopyLink, isFalse);
    expect(outcome.failure!.stage, ReferralInviteStage.createReferral);
    expect(outcome.failure!.errorCode, 'failed-precondition');
    expect(reported, hasLength(1));
  });

  test('link building failure or an unusable invitation: reported, nothing kept', () async {
    final thrown = await tap(shared, buildInvite: (_, __) => throw const FormatException('bad'));
    expect(thrown.failure!.stage, ReferralInviteStage.buildLink);
    final empty = await tap(shared,
        buildInvite: (_, at) => PreparedReferralInvite(code: '', link: '', text: '', createdAt: at));
    expect(empty.failure!.stage, ReferralInviteStage.buildLink);
    expect(empty.canCopyLink, isFalse);
    await tap(shared);
    expect(created, 3, reason: 'no broken invitation is reused');
  });

  test('diagnostics never carry the code, links, addresses or identifiers', () {
    final failure = ReferralInviteFailure.of(
      ReferralInviteStage.openShare,
      PlatformException(
          code: 'Share failed',
          message: 'ref ABCDEF01 https://play.proxiplay.fr/i?ref=ABCDEF01 a.b@c.fr uid AbCdEfGhIjKlMnOpQrStUvWx12'),
      secret: 'ABCDEF01',
    );
    expect(failure.logLine, isNot(contains('ABCDEF01')));
    expect(failure.logLine, isNot(contains('proxiplay.fr')));
    expect(failure.logLine, isNot(contains('@')));
    expect(failure.logLine, isNot(contains('AbCdEfGhIjKlMnOpQrStUvWx12')));
    expect(failure.logLine, contains('stage=openShare type=PlatformException code=Share failed'));
    expect(failure.analyticsParameters.keys, {'stage', 'error_type', 'error_code'});
  });

  group('share_plus 10.0.2 on Android (platform channel)', () {
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null));

    Future<ShareResultStatus> realShare(String text) async =>
        (await Share.share(text, subject: 'Inviter un ami sur ProxiPlay')).status;

    test('a native "Share failed" error surfaces as the openShare step, link kept', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        throw PlatformException(code: 'Share failed', message: 'Unable to start activity');
      });
      final outcome = await tap(realShare);
      expect(outcome.failure!.stage, ReferralInviteStage.openShare);
      expect(outcome.failure!.errorCode, 'Share failed');
      expect(outcome.canCopyLink, isTrue);
    });

    test('the plugin results map to shared, dismissed and uncertain', () async {
      for (final entry in {
        'com.whatsapp': ReferralInviteStatus.shared,
        '': ReferralInviteStatus.dismissed,
        'dev.fluttercommunity.plus/share/unavailable': ReferralInviteStatus.uncertain,
      }.entries) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, (_) async => entry.key);
        expect((await tap(realShare)).status, entry.value, reason: entry.key);
      }
    });
  });

  test('the page wires the flow, the copy fallback and the iPad anchor', () {
    final page = File('lib/pages/joueur/parrainage_joueur_page/parrainage_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(page, contains('await runReferralInvite('));
    expect(page, contains("label: 'Copier le lien'"));
    expect(page, contains('Clipboard.setData(ClipboardData(text: link))'));
    expect(page, contains('onCopied: () => unsentReferralInvites.handedOver(currentUserUid)'));
    expect(page, contains('sharePositionOrigin: _shareOrigin(anchor)'));
    expect(page, contains('key: _inviteButtonKey'));
    expect(page, contains("logFirebaseEvent('referral_invite_failed'"));
    // Only one place creates an invitation, inside the flow.
    expect('createReferral('.allMatches(page).length, 1);
  });
}
