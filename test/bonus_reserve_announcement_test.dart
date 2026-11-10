import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:proxi_play/components/bonus_reserve_announcement_dialog.dart';
import 'package:proxi_play/utils/bonus_reserve_announcement.dart';

/// Simule une fermeture puis une reouverture de l'app : la memoire de
/// session est perdue, le stockage local est conserve.
void relaunchApp() => resetBonusReserveAnnouncementSession();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    relaunchApp();
  });

  test('textes valides de l annonce', () {
    expect(bonusReserveAnnouncementTitle, 'Vos parties bonus restent à vous ! 🎉');
    expect(
      bonusReserveAnnouncementBody,
      'Bonne nouvelle ! Les parties bonus gagnées sur ProxiPlay sont désormais '
      'conservées, même après minuit. Cumulez-les et utilisez-les quand vous '
      'voulez, en plus de vos 3 parties quotidiennes.',
    );
    expect(bonusReserveAnnouncementButton, 'Compris !');
  });

  test('affichee une seule fois, y compris apres reouverture de l app', () async {
    expect(await takeBonusReserveAnnouncement('playerA'), isTrue);
    expect(await takeBonusReserveAnnouncement('playerA'), isFalse);
    relaunchApp();
    expect(await takeBonusReserveAnnouncement('playerA'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(bonusReserveAnnouncementPrefsKey('playerA')), isTrue);
  });

  test('deconnexion puis changement de compte : chaque compte la voit une fois',
      () async {
    expect(await takeBonusReserveAnnouncement('playerA'), isTrue);
    // Deconnexion de A, connexion de B sur le meme appareil.
    relaunchApp();
    expect(await takeBonusReserveAnnouncement('playerB'), isTrue);
    // Retour de A : deja vue.
    relaunchApp();
    expect(await takeBonusReserveAnnouncement('playerA'), isFalse);
    expect(await takeBonusReserveAnnouncement('playerB'), isFalse);
  });

  test('deux demandes simultanees n affichent qu une fenetre', () async {
    final results = await Future.wait([
      takeBonusReserveAnnouncement('playerA'),
      takeBonusReserveAnnouncement('playerA'),
    ]);
    expect(results.where((shown) => shown).length, 1);
  });

  test('sans compte : jamais affichee', () async {
    expect(await takeBonusReserveAnnouncement(''), isFalse);
  });

  test('audience : joueurs connectes seulement', () {
    bool audience(String uid, {bool guest = false, String? role}) =>
        isBonusReserveAnnouncementAudience(
            accountId: uid, isGuestOrAnonymous: guest, userRole: role);
    expect(audience('u', role: 'joueur'), isTrue);
    // Profil pas encore charge : le joueur la voit quand meme.
    expect(audience('u'), isTrue);
    expect(audience('u', guest: true), isFalse);
    expect(audience(''), isFalse);
    expect(audience('u', role: 'commercant'), isFalse);
    expect(audience('u', role: 'admin'), isFalse);
  });

  testWidgets('la fenetre affiche le texte et se ferme avec « Compris ! »',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const BonusReserveAnnouncementDialog(),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text(bonusReserveAnnouncementTitle), findsOneWidget);
    expect(find.text(bonusReserveAnnouncementBody), findsOneWidget);
    await tester.tap(find.text('Compris !'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bonus-reserve-announcement')),
        findsNothing);
  });

  testWidgets('petit ecran et grand texte : pas de debordement', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.6)),
      child: MaterialApp(home: Scaffold(body: BonusReserveAnnouncementDialog())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Compris !'), findsOneWidget);
  });

  test('l accueil presente l annonce sans rien ecrire sur le serveur', () {
    final home = File(
            'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(home, contains('_presentBonusReserveAnnouncement()'));
    expect(home, contains('isBonusReserveAnnouncementAudience('));
    expect(home, contains('takeBonusReserveAnnouncement(currentUserUid)'));
    expect(home, contains('const BonusReserveAnnouncementDialog()'));
    final util = File('lib/utils/bonus_reserve_announcement.dart')
        .readAsStringSync();
    expect(util, isNot(contains('cloud_firestore')));
    expect(util, isNot(contains('cloud_functions')));
  });

  test('la deconnexion n efface pas le stockage local', () {
    for (final path in [
      'lib/auth/firebase_auth/firebase_auth_manager.dart',
      'lib/auth/auth_manager.dart',
      'lib/auth/firebase_auth/account_routing.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('SharedPreferences')), reason: path);
    }
  });
}
