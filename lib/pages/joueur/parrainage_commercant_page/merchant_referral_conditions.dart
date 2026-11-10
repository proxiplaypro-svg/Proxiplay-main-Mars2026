import 'package:flutter/material.dart';

import '/utils/merchant_referral_conditions.dart';

typedef MerchantReferralConditionsLoader
    = Future<MerchantReferralConditionsResult> Function();

/// Conditions du programme de parrainage commercant, chargees a chaque
/// ouverture depuis app_config/merchant_referral (1.1.4). Une copie locale
/// (cache de l'appareil ou version integree) est toujours signalee.
class MerchantReferralConditionsDialog extends StatefulWidget {
  const MerchantReferralConditionsDialog({super.key, this.loader});

  /// Injection pour les tests ; par defaut, lecture Firestore.
  final MerchantReferralConditionsLoader? loader;

  @override
  State<MerchantReferralConditionsDialog> createState() =>
      _MerchantReferralConditionsDialogState();
}

class _MerchantReferralConditionsDialogState
    extends State<MerchantReferralConditionsDialog> {
  MerchantReferralConditionsResult? _result;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Chaque ouverture et chaque « Réessayer » relisent la configuration ;
  /// seule la reponse de la derniere demande est affichee.
  Future<void> _load() async {
    final request = ++_request;
    if (_result != null) setState(() => _result = null);
    final result = await (widget.loader ?? loadMerchantReferralConditions)();
    if (!mounted || request != _request) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      key: const ValueKey('merchant-referral-conditions'),
      // Toute la fenetre defile : titre long et grand texte sur petit ecran.
      scrollable: true,
      title: Text(result?.conditions.title ?? 'Conditions du programme'),
      content: result == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: CircularProgressIndicator(
                  key: ValueKey('merchant-referral-conditions-loading'),
                ),
              ),
            )
          : _ConditionsBody(result: result, onRetry: _load),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _ConditionsBody extends StatelessWidget {
  const _ConditionsBody({required this.result, required this.onRetry});

  final MerchantReferralConditionsResult result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notice = result.notice;
    final versionLabel = conditionsVersionLabel(result.conditions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notice != null)
          Container(
            key: const ValueKey('merchant-referral-conditions-notice'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: const Color(0xFFF0C58A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18.0, color: Color(0xFF8A5300)),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(notice,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6B4100))),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('Réessayer'),
                  ),
                ),
              ],
            ),
          ),
        if (versionLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Text(versionLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFF6B6B8B))),
          ),
        for (final block in result.conditions.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: switch (block) {
              ConditionsParagraph(:final text) => Text(text),
              ConditionsList(:final items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(item)),
                          ],
                        ),
                      ),
                  ],
                ),
            },
          ),
      ],
    );
  }
}
