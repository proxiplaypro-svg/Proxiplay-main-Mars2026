import '/backend/backend.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/widgets/proxiplay_network_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeSearchResultCard extends StatelessWidget {
  const HomeSearchResultCard({
    super.key,
    required this.game,
    required this.onTap,
  });

  final GamesRecord game;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: StreamBuilder<EnseignesRecord>(
        stream: EnseignesRecord.getDocument(game.enseigneId!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }

          final enseigne = snapshot.data!;

          return InkWell(
            splashColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: () async {
              await onTap();
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    height: 130.0,
                    decoration: const BoxDecoration(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: ProxiplayNetworkImage(
                        imageUrl: game.photo,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        10.0, 0.0, 0.0, 0.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.name,
                          style: FlutterFlowTheme.of(context).bodyMedium.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _infoRow(
                              context,
                              icon: Icons.store_sharp,
                              text: enseigne.name,
                            ),
                            _infoRow(
                              context,
                              icon: Icons.location_on_sharp,
                              text: enseigne.city,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Icon(
                                  FontAwesomeIcons.piggyBank,
                                  color: FlutterFlowTheme.of(context).primaryText,
                                  size: 18.0,
                                ),
                                _smallText(context, ' Valeur : '),
                                _smallText(
                                  context,
                                  game.prizeValue == 0
                                      ? 'Gains instantan\u00E9s'
                                      : compactEuroAmount(game.prizeValue),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Icon(
                                  Icons.calendar_month,
                                  color: FlutterFlowTheme.of(context).primaryText,
                                  size: 18.0,
                                ),
                                _smallText(context, ' Valable jusqu\'au : '),
                                _smallText(
                                  context,
                                  dateTimeFormat(
                                    'd/M/y',
                                    game.endDate!,
                                    locale: FFLocalizations.of(context).languageCode,
                                  ),
                                ),
                              ],
                            ),
                          ].divide(const SizedBox(height: 5.0)),
                        ),
                      ].divide(const SizedBox(height: 5.0)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Icon(
          icon,
          color: FlutterFlowTheme.of(context).primaryText,
          size: 18.0,
        ),
        _smallText(context, text),
      ],
    );
  }

  Widget _smallText(BuildContext context, String text) {
    return Text(
      text,
      style: FlutterFlowTheme.of(context).bodySmall.override(
            font: GoogleFonts.inter(
              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
            ),
            letterSpacing: 0.0,
            fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
            fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
          ),
    );
  }
}
