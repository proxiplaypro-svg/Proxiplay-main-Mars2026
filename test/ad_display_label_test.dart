import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/services/ad_system_service.dart';
import 'package:proxi_play/utils/ad_system_utils.dart';

// "Libellé affiché dans l'application" (Admin, display_label): replaces the
// type label for a campaign; older campaigns keep "Publicité".
void main() {
  test('the free label wins, otherwise the type label ("Publicité" by default)', () {
    expect(adDisplayLabel(), 'Publicité', reason: 'older campaign without the field');
    expect(adDisplayLabel(displayLabel: '', communicationType: 'discovery'), 'À découvrir');
    expect(adDisplayLabel(displayLabel: '   ', communicationType: 'proxiplay_info'), 'Info ProxiPlay');
    expect(adDisplayLabel(displayLabel: '  Partenaire   local ', communicationType: 'discovery'),
        'Partenaire local');
    expect(adDisplayLabel(displayLabel: 42), 'Publicité', reason: 'unexpected type ignored');
  });

  test('never longer than the Admin limit, an emoji counting as one character', () {
    expect(kAdDisplayLabelMaxLength, 24);
    expect(adDisplayLabel(displayLabel: 'x' * 24), 'x' * 24);
    expect(adDisplayLabel(displayLabel: 'x' * 30), 'x' * 24);
    expect(adDisplayLabel(displayLabel: '${'x' * 23}🎉'), '${'x' * 23}🎉');
  });

  test('the placement config exposes the resolved label', () {
    const base = AdPlacementConfig(
        enabled: true, imageUrl: 'i', destinationUrl: '', startAt: null, endAt: null, frequencyCapHours: null);
    expect(base.communicationLabel, 'Publicité');
    const custom = AdPlacementConfig(
        enabled: true, imageUrl: 'i', destinationUrl: '', startAt: null, endAt: null, frequencyCapHours: null,
        displayLabel: 'Offre du mois');
    expect(custom.communicationLabel, 'Offre du mois');
    expect(custom.withCreative(imageUrl: '', destinationUrl: '').communicationLabel, 'Offre du mois',
        reason: 'kept for adults-only campaigns');
  });
}
