import 'dart:async';

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/services/ad_system_service.dart';
import '/utils/ad_system_utils.dart';

/// Publicite plein ecran a l'ouverture (vendue en direct par ProxiPlay, pas
/// AdMob), reservee a l'accueil joueur : elle enveloppe uniquement cette page,
/// jamais l'accueil commercant, la connexion ou un jeu ouvert par QR code.
///
/// Fail-open par construction : `widget.child` est TOUJOURS construit ;
/// l'interstitiel n'est qu'une superposition, montree seulement si la config
/// et l'image sont pretes dans le delai imparti (2 s) ET que l'accueil est
/// toujours l'ecran visible. Passe ce delai, l'affichage est abandonne pour
/// ce lancement : jamais d'apparition tardive sous le doigt du joueur.
///
/// Une seule tentative par processus (lancement a froid) : un drapeau
/// statique, pour qu'un retour a l'accueil ou depuis l'arriere-plan ne la
/// redeclenche pas.
class OpenAdGate extends StatefulWidget {
  const OpenAdGate({
    super.key,
    required this.child,
    required this.signedIn,
    this.readyDeadline = const Duration(seconds: 2),
    @visibleForTesting this.service,
    @visibleForTesting this.imageProviderFor,
  });

  final Widget child;
  // Adults-only campaigns are only resolved for a signed-in account.
  final bool signedIn;
  final Duration readyDeadline;
  final AdSystemService? service;
  final ImageProvider Function(String url)? imageProviderFor;

  /// Lets a test simulate a new cold start.
  @visibleForTesting
  static void resetAttemptForTest() =>
      _OpenAdGateState._attemptedThisProcess = false;

  @override
  State<OpenAdGate> createState() => _OpenAdGateState();
}

class _OpenAdGateState extends State<OpenAdGate> {
  static bool _attemptedThisProcess = false;

  late final AdSystemService _service = widget.service ?? AdSystemService();
  AdPlacementConfig? _readyAd;
  bool _dismissed = false;

  ImageProvider _image(String url) =>
      widget.imageProviderFor?.call(url) ?? NetworkImage(url);

  @override
  void initState() {
    super.initState();
    if (!_attemptedThisProcess) {
      _attemptedThisProcess = true;
      // precacheImage needs inherited widgets: wait for the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_tryShow());
      });
    }
  }

  Future<AdPlacementConfig?> _prepare() async {
    final config = await _service.getDisplayablePlacement(
      'open',
      signedIn: widget.signedIn,
    );
    final eligible = shouldShowOpenAd(
      enabled: config.enabled,
      startAt: config.startAt,
      endAt: config.endAt,
      lastShownAt: FFAppState().adOpenLastShownAt,
      frequencyCapHours: config.frequencyCapHours,
      now: DateTime.now(),
    );
    if (!eligible || !config.hasUsableCreative || !mounted) return null;
    // Never a full-screen frame with a broken or missing image.
    await precacheImage(_image(config.imageUrl), context);
    return config;
  }

  Future<void> _tryShow() async {
    AdPlacementConfig? config;
    try {
      config = await _prepare().timeout(widget.readyDeadline);
    } catch (_) {
      // Fail-open: network, Firestore, image or deadline -> no ad, no late
      // appearance for this launch.
      return;
    }
    if (config == null || !mounted) return;
    // Only over the player Home itself, never over a screen pushed on top
    // (e.g. a game opened from a QR code).
    if (ModalRoute.of(context)?.isCurrent == false) return;
    FFAppState().adOpenLastShownAt = DateTime.now();
    setState(() => _readyAd = config);
    final shown = config;
    // Counted once actually on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _readyAd == shown && !_dismissed) {
        unawaited(
            _service.recordImpression('open', campaignId: shown.campaignId));
      }
    });
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  Future<void> _handleTap() async {
    final ad = _readyAd;
    _dismiss();
    if (ad == null || ad.destinationUrl.isEmpty) {
      return;
    }
    unawaited(_service.recordClick('open', campaignId: ad.campaignId));
    try {
      await launchURL(ad.destinationUrl);
    } catch (_) {
      // Une destination mal configuree ne doit jamais faire planter l'app.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _readyAd;
    final showOverlay = ad != null && !_dismissed;

    // While the ad is shown, Android back closes it and nothing else.
    return PopScope(
      canPop: !showOverlay,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showOverlay) _dismiss();
      },
      child: Stack(
        children: [
          widget.child,
          if (showOverlay)
            Positioned.fill(
              child: Material(
                key: const ValueKey('open-ad-overlay'),
                color: Colors.black,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _handleTap,
                          child: Image(
                            image: _image(ad.imageUrl),
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) => _dismiss());
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12.0,
                        left: 12.0,
                        // Never under the close button, whatever the label.
                        right: 64.0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            // Same label as the Home banners: "Publicité",
                            // "À découvrir" or "Info ProxiPlay" (older or
                            // unknown campaigns: "Publicité").
                            child: Text(
                              ad.communicationLabel,
                              key: const ValueKey('open-ad-label'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12.0,
                        right: 12.0,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _dismiss,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 24.0,
                                semanticLabel: 'Fermer la publicité',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
