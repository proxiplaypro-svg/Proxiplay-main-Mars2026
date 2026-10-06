import 'dart:async';

import 'package:flutter/material.dart';

import '/app_state.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/services/ad_system_service.dart';
import '/utils/ad_system_utils.dart';

/// Publicite plein ecran a l'ouverture de l'application (vendue en direct
/// par ProxiPlay, pas AdMob). Fail-open par construction : `widget.child`
/// (l'application normale) est TOUJOURS construit et affiche en premier ;
/// l'interstitiel n'est qu'une superposition ajoutee par-dessus, et
/// seulement si la config + l'image ont ete chargees avec succes dans un
/// delai court. Toute erreur reseau/Firestore/image, ou tout depassement
/// de delai, laisse l'application fonctionner normalement, sans aucun
/// ecran bloquant.
///
/// Tente le chargement une seule fois par processus (cold start) : un
/// drapeau statique, pas une variable d'instance, pour survivre a un
/// rebuild de MaterialApp (changement de theme/locale) qui recreerait
/// sinon ce widget et redeclencherait l'essai.
class OpenAdGate extends StatefulWidget {
  const OpenAdGate({super.key, required this.child});

  final Widget child;

  @override
  State<OpenAdGate> createState() => _OpenAdGateState();
}

class _OpenAdGateState extends State<OpenAdGate> {
  static bool _attemptedThisProcess = false;

  final _service = AdSystemService();
  AdPlacementConfig? _readyAd;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (!_attemptedThisProcess) {
      _attemptedThisProcess = true;
      unawaited(_tryLoadAd());
    }
  }

  Future<void> _tryLoadAd() async {
    try {
      final config = await _service
          .getPlacementConfig('open')
          .timeout(const Duration(seconds: 4));
      final now = DateTime.now();
      final eligible = shouldShowOpenAd(
        enabled: config.enabled,
        startAt: config.startAt,
        endAt: config.endAt,
        lastShownAt: FFAppState().adOpenLastShownAt,
        frequencyCapHours: config.frequencyCapHours,
        now: now,
      );
      if (!eligible || !config.hasUsableCreative) {
        return;
      }

      if (!mounted) return;
      // Jamais d'ecran plein ecran sur une image cassee/absente : on la
      // precharge d'abord, avec son propre delai.
      await precacheImage(NetworkImage(config.imageUrl), context)
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;
      FFAppState().adOpenLastShownAt = now;
      setState(() {
        _readyAd = config;
      });
      unawaited(_service.recordImpression('open'));
    } catch (_) {
      // Fail-open : reseau, Firestore, timeout ou image cassee -> aucune
      // pub affichee, l'application continue normalement.
    }
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
    unawaited(_service.recordClick('open'));
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

    return Stack(
      children: [
        widget.child,
        if (showOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.black,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _handleTap,
                        child: Image.network(
                          ad.imageUrl,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            // Deja precharge avec succes plus haut ; filet
                            // de securite si l'image devient indisponible
                            // entre-temps -- on referme plutot que de
                            // laisser un cadre casse a l'ecran.
                            WidgetsBinding.instance
                                .addPostFrameCallback((_) => _dismiss());
                            return const SizedBox.shrink();
                          },
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
    );
  }
}
