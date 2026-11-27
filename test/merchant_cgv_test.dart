import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/firebase_auth/account_routing_logic.dart';
import 'package:proxi_play/backend/schema/enums/enums.dart';
import 'package:proxi_play/utils/merchant_cgv.dart';

void main() {
  group('constantes CGV', () {
    test('texte validé, version 2.1 et lien du PDF', () {
      expect(kMerchantCgvVersion, '2.1');
      expect(kMerchantCgvCheckboxText,
          "J'ai lu et j'accepte les conditions générales de vente PROXIPLAY (version 2.1, applicables à compter du 1er décembre 2026).");
      expect(kMerchantCgvUrl,
          'https://www.proxiplay.fr/legal-content/sections/CGV.pdf');
      expect(kMerchantCgvCheckboxText.contains(kMerchantCgvLinkText), isTrue);
    });
  });

  group('MerchantCgvCheckbox', () {
    Future<List<Uri>> pumpBox(WidgetTester tester, ValueNotifier<bool> value) async {
      final opened = <Uri>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, current, __) => MerchantCgvCheckbox(
              value: current,
              onChanged: (next) => value.value = next,
              openUrl: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        ),
      ));
      return opened;
    }

    testWidgets('affiche le texte exact, case non cochée', (tester) async {
      final value = ValueNotifier(false);
      await pumpBox(tester, value);
      final text = tester.widget<Text>(find.byKey(const ValueKey('merchant_cgv_text')));
      expect(text.textSpan!.toPlainText(), kMerchantCgvCheckboxText);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('le lien s\'ouvre par simple appui, sans cocher la case', (tester) async {
      final value = ValueNotifier(false);
      final opened = await pumpBox(tester, value);
      await tester.tapOnText(find.textRange.ofSubstring(kMerchantCgvLinkText));
      await tester.pump();
      expect(opened, [Uri.parse(kMerchantCgvUrl)]);
      expect(value.value, isFalse);
    });

    testWidgets('la case et le reste du texte cochent / décochent', (tester) async {
      final value = ValueNotifier(false);
      final opened = await pumpBox(tester, value);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(value.value, isTrue);
      await tester.tapOnText(find.textRange.ofSubstring('PROXIPLAY (version 2.1'));
      await tester.pump();
      expect(value.value, isFalse);
      expect(opened, isEmpty);
    });

    testWidgets('le TapGestureRecognizer est libéré au démontage', (tester) async {
      final value = ValueNotifier(false);
      await pumpBox(tester, value);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('applyMerchantCgvRequirement', () {
    AuthenticatedHomeTarget apply(AuthenticatedHomeTarget target, Roles? role, String? version) =>
        applyMerchantCgvRequirement(target: target, effectiveRole: role, cgvAcceptedVersion: version);

    test('commerçant sans cgv_accepted_version : écran CGV, prioritaire', () {
      for (final target in [
        AuthenticatedHomeTarget.commercantHome,
        AuthenticatedHomeTarget.waitingValidation,
        AuthenticatedHomeTarget.rejected,
      ]) {
        expect(apply(target, Roles.commercant, null), AuthenticatedHomeTarget.merchantCgvRequired);
        expect(apply(target, Roles.commercant, ''), AuthenticatedHomeTarget.merchantCgvRequired);
        expect(apply(target, Roles.commercant, '  '), AuthenticatedHomeTarget.merchantCgvRequired);
      }
    });

    test('commerçant avec une version acceptée : routage habituel', () {
      for (final target in [
        AuthenticatedHomeTarget.commercantHome,
        AuthenticatedHomeTarget.waitingValidation,
        AuthenticatedHomeTarget.rejected,
      ]) {
        expect(apply(target, Roles.commercant, '2.1'), target);
      }
    });

    test('joueur et admin : aucun effet', () {
      expect(apply(AuthenticatedHomeTarget.joueurHome, Roles.joueur, null), AuthenticatedHomeTarget.joueurHome);
      expect(apply(AuthenticatedHomeTarget.rejected, Roles.joueur, null), AuthenticatedHomeTarget.rejected);
      expect(apply(AuthenticatedHomeTarget.adminHome, Roles.admin, null), AuthenticatedHomeTarget.adminHome);
    });

    test('conflit de rôle ou fiche absente : inchangé', () {
      expect(apply(AuthenticatedHomeTarget.routingIssue, Roles.commercant, null), AuthenticatedHomeTarget.routingIssue);
    });

    test('enchaîné avec resolveTargetFromResolvedRole', () {
      AuthenticatedHomeTarget resolve(AccountStatus? status, String? version) => apply(
            resolveTargetFromResolvedRole(
              documentExists: true,
              effectiveRole: Roles.commercant,
              playerSignals: const [],
              accountStatus: status,
            ),
            Roles.commercant,
            version,
          );
      expect(resolve(AccountStatus.pendingValidation, null), AuthenticatedHomeTarget.merchantCgvRequired);
      expect(resolve(AccountStatus.pendingValidation, '2.1'), AuthenticatedHomeTarget.waitingValidation);
      expect(resolve(null, '2.1'), AuthenticatedHomeTarget.commercantHome);
    });
  });
}
