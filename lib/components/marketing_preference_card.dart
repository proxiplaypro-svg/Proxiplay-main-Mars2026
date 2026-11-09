import 'package:flutter/material.dart';

import '/utils/marketing_consent_state.dart';

const _ink = Color(0xFF2D2A72);
const _muted = Color(0xFF6B6B8B);

/// Optional email preference, in the style of the profile cards. It only
/// displays [state]: the stored value changes once the server has confirmed
/// it (no optimistic agreement).
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

  @override
  Widget build(BuildContext context) {
    final enabled = state == MarketingConsentState.granted;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: const Key('marketing-preference-card-surface'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FF),
                borderRadius: BorderRadius.circular(15),
              ),
              child:
                  const Icon(Icons.mail_outline_rounded, color: _ink, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MergeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recevoir les actualités de ProxiPlay',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.2)),
                    const SizedBox(height: 4),
                    const Text('Nouveaux jeux, cadeaux et actualités',
                        key: Key('marketing-preference-subtitle'),
                        style: TextStyle(
                            color: _muted, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
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
      ),
    );
  }
}
