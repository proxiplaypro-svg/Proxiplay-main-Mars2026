import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// CGV commerçant : texte et version définis une seule fois côté app.
/// Doivent rester identiques aux constantes de
/// firebase/functions/merchant_cgv_acceptance.js (test
/// merchant_cgv_acceptance.test.js). Chaque constante tient sur une ligne,
/// entre guillemets doubles, pour que ce test puisse la relire.
const kMerchantCgvVersion = "2.1";
const kMerchantCgvCheckboxText = "J'ai lu et j'accepte les conditions générales de vente PROXIPLAY (version 2.1, applicables à compter du 1er décembre 2026).";
const kMerchantCgvUrl = "https://www.proxiplay.fr/legal-content/sections/CGV.pdf";

/// Partie du texte rendue comme lien vers [kMerchantCgvUrl].
const kMerchantCgvLinkText = 'conditions générales de vente';

/// Ouvre une URL ; injectable pour les tests.
typedef MerchantCgvUrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpener(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Origine de l'acceptation enregistrée côté serveur.
enum MerchantCgvSource { signup, login }

/// Enregistre l'acceptation côté serveur (callable
/// recordMerchantCgvAcceptance, région us-central1). Seul le serveur écrit
/// users/{uid}.cgv_accepted_version et la trace pour l'admin.
Future<void> recordMerchantCgvAcceptance(
  MerchantCgvSource source, {
  FirebaseFunctions? functions,
}) async {
  await (functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'))
      .httpsCallable('recordMerchantCgvAcceptance')
      .call(<String, dynamic>{'accepted': true, 'source': source.name});
}

/// Case « J'accepte les CGV » (non précochée par l'appelant). Un appui sur
/// « conditions générales de vente » ouvre le PDF ; un appui sur le reste du
/// texte coche ou décoche la case.
class MerchantCgvCheckbox extends StatefulWidget {
  const MerchantCgvCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.openUrl,
    this.textStyle,
    this.accentColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final MerchantCgvUrlOpener? openUrl;

  /// Style du texte (thème de l'écran appelant) et couleur de la case et du lien.
  final TextStyle? textStyle;
  final Color? accentColor;

  @override
  State<MerchantCgvCheckbox> createState() => _MerchantCgvCheckboxState();
}

class _MerchantCgvCheckboxState extends State<MerchantCgvCheckbox> {
  late final TapGestureRecognizer _linkRecognizer;

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = _openCgv;
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openCgv() async {
    try {
      await (widget.openUrl ?? _defaultOpener)(Uri.parse(kMerchantCgvUrl));
    } catch (_) {
      // Aucun navigateur disponible : la case reste utilisable.
    }
  }

  void _toggle() {
    if (widget.enabled) widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        widget.textStyle ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final linkStart = kMerchantCgvCheckboxText.indexOf(kMerchantCgvLinkText);
    final linkEnd = linkStart + kMerchantCgvLinkText.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: const ValueKey('merchant_cgv_checkbox'),
          value: widget.value,
          onChanged: widget.enabled
              ? (newValue) => widget.onChanged(newValue ?? false)
              : null,
          activeColor: accent,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                key: const ValueKey('merchant_cgv_text'),
                TextSpan(
                  style: baseStyle,
                  children: [
                    TextSpan(
                        text: kMerchantCgvCheckboxText.substring(0, linkStart)),
                    TextSpan(
                      text: kMerchantCgvLinkText,
                      style: baseStyle.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        color: accent,
                      ),
                      recognizer: _linkRecognizer,
                    ),
                    TextSpan(text: kMerchantCgvCheckboxText.substring(linkEnd)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
