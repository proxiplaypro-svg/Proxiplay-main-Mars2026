import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LotsSummaryCard extends StatelessWidget {
  const LotsSummaryCard({
    super.key,
    required this.totalLots,
    required this.unclaimedLots,
  });

  static const Color _logoBlue = Color(0xFF8AA4D6);
  static const Color _logoBlueTint = Color(0xFFF2F5FB);

  final int totalLots;
  final int unclaimedLots;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(18.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 18.0,
              offset: const Offset(0.0, 8.0),
            ),
          ],
        ),
        child: Padding(
          padding:
              const EdgeInsetsDirectional.fromSTEB(20.0, 18.0, 20.0, 18.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total des Lots',
                      style: FlutterFlowTheme.of(context).headlineSmall.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .headlineSmall
                                  .fontStyle,
                            ),
                            fontSize: 20.0,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      totalLots > 0
                          ? '$totalLots lot${totalLots > 1 ? 's' : ''} gagné${totalLots > 1 ? 's' : ''}'
                          : 'Aucun lot gagné',
                      style: FlutterFlowTheme.of(context).bodyLarge.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .fontStyle,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (totalLots > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '$unclaimedLots non réclamé${unclaimedLots > 1 ? 's' : ''}',
                          style: FlutterFlowTheme.of(context).bodyMedium.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                color: FlutterFlowTheme.of(context).primary,
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: 52.0,
                height: 52.0,
                decoration: BoxDecoration(
                  color: _logoBlueTint,
                  borderRadius: BorderRadius.circular(16.0),
                  boxShadow: [
                    BoxShadow(
                      color: _logoBlue.withValues(alpha: 0.10),
                      blurRadius: 12.0,
                      offset: const Offset(0.0, 4.0),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: _logoBlue,
                  size: 26.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
