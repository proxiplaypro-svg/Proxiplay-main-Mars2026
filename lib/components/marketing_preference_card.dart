import 'package:flutter/material.dart';

import '/config/marketing_consent.dart';
import '/utils/marketing_consent_state.dart';

const _ink = Color(0xFF2D2A72);
const _muted = Color(0xFF6B6B8B);

/// Optional email preference, in the style of the profile cards. The
/// description is the exact consent text of [kMarketingPlayerTextVersion].
/// It only displays [state]: the stored value changes once the server has
/// confirmed it (no optimistic agreement).
class MarketingPreferenceCard extends StatelessWidget {
  const MarketingPreferenceCard({
    super.key,
    required this.state,
    required this.saving,
    required this.onChanged,
  });

  final MarketingConsentState state;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  String get _status => switch (state) {
        MarketingConsentState.unanswered => 'Aucune préférence enregistrée',
        MarketingConsentState.granted => 'Activé',
        MarketingConsentState.withdrawn => 'Désactivé',
      };

  @override
  Widget build(BuildContext context) {
    final enabled = state == MarketingConsentState.granted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(17, 16, 10, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child:
                const Icon(Icons.mail_outline_rounded, color: _ink, size: 25),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Actualités par e-mail',
                      style: TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2)),
                  const SizedBox(height: 4),
                  const Text(kMarketingPlayerConsentText,
                      key: Key('marketing-consent-text'),
                      style:
                          TextStyle(color: _muted, fontSize: 13, height: 1.35)),
                  const SizedBox(height: 6),
                  Text('Facultatif · $_status',
                      key: const Key('marketing-consent-status'),
                      style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            height: 48,
            child: Center(
              child: saving
                  ? const SizedBox(
                      key: Key('marketing-consent-saving'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Semantics(
                      label: 'Actualités par e-mail',
                      child: Switch(
                        key: const Key('marketing-consent-switch'),
                        value: enabled,
                        activeThumbColor: Colors.white,
                        activeTrackColor: const Color(0xFFA0134D),
                        onChanged: onChanged,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
