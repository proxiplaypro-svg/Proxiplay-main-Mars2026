import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/player_bonus_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_bar_joueur_model.dart';
export 'app_bar_joueur_model.dart';

class AppBarJoueurWidget extends StatefulWidget {
  const AppBarJoueurWidget({super.key});

  @override
  State<AppBarJoueurWidget> createState() => _AppBarJoueurWidgetState();
}

class _AppBarJoueurWidgetState extends State<AppBarJoueurWidget> {
  late AppBarJoueurModel _model;

  @override
  void setState(VoidCallback callback) {
    super.setState(callback);
    _model.onUpdate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AppBarJoueurModel());
  }

  @override
  void dispose() {
    _model.maybeDispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 10.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: SvgPicture.asset(
              'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
              width: 200.0,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Flexible(
          child: AuthUserStreamWidget(
            builder: (context) {
              if (currentUserUid == '') {
                return Container(
                  decoration: const BoxDecoration(),
                );
              }

              final remainingPart =
                  valueOrDefault<int>(currentUserDocument?.remainingPart, 0);
              final playerAccessState = resolvePlayerAccessState(
                currentUserDocument,
                now: getCurrentTimestamp,
              );
              final isBonusActive =
                  playerAccessState == PlayerAccessState.bonusActive;
              final isReferralBonusActive =
                  isBonusActive && currentUserDocument?.bonusSource.trim() == 'referral';

              return Container(
                decoration: BoxDecoration(
                  color: isBonusActive
                      ? const Color(0xFFA0134D)
                      : remainingPart == 1
                          ? const Color(0xFFA0134D)
                          : FlutterFlowTheme.of(context).primary,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    width: 0.0,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                  child: Container(
                    decoration: const BoxDecoration(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              isReferralBonusActive
                                  ? 'Bonus'
                                  : remainingPart.toString(),
                              style: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                            ),
                            Text(
                              isBonusActive
                                  ? 'actif'
                                  : remainingPart == 1
                                      ? 'chance'
                                      : 'chances',
                              style: FlutterFlowTheme.of(context)
                                  .labelMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                            ),
                          ].divide(const SizedBox(width: 4.0)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
