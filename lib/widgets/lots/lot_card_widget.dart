import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LotCard extends StatelessWidget {
  const LotCard({
    super.key,
    required this.merchantLabel,
    required this.prizeName,
    required this.winDateLabel,
    required this.claimed,
    required this.isDeleting,
    required this.onTap,
    required this.onDelete,
  });

  static const Color _logoBlue = Color(0xFF8AA4D6);
  static const Color _logoOrangeTint = Color(0xFFFFF3EE);
  static const Color _logoBlueTint = Color(0xFFF2F5FB);
  static const Color _deleteTint = Color(0xFFFFF1F3);
  static const Color _deleteAccent = Color(0xFFA0134D);

  final String merchantLabel;
  final String prizeName;
  final String winDateLabel;
  final bool claimed;
  final bool isDeleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Widget _buildBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8.0, 5.0, 8.0, 5.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12.0,
              color: textColor,
            ),
            const SizedBox(width: 5.0),
            Text(
              label,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
                    color: textColor,
                    fontSize: 11.0,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLotThumbnail() {
    return Container(
      width: 48.0,
      height: 48.0,
      decoration: BoxDecoration(
        color: _logoBlueTint,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: _logoBlue.withValues(alpha: 0.08),
            blurRadius: 10.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.card_giftcard_rounded,
          color: _logoBlue,
          size: 24.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Container(
          width: MediaQuery.sizeOf(context).width,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(20.0),
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
                const EdgeInsetsDirectional.fromSTEB(14.0, 14.0, 14.0, 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLotThumbnail(),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            merchantLabel,
                            style: FlutterFlowTheme.of(context)
                                .titleMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.w800,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                                  fontSize: 20.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            prizeName,
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                  fontSize: 14.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Container(
                      width: 40.0,
                      height: 40.0,
                      decoration: BoxDecoration(
                        color: _deleteTint,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: IconButton(
                        onPressed: isDeleting ? null : onDelete,
                        padding: EdgeInsets.zero,
                        splashRadius: 18.0,
                        tooltip: 'Supprimer',
                        visualDensity: VisualDensity.compact,
                        icon: isDeleting
                            ? const SizedBox(
                                width: 18.0,
                                height: 18.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _deleteAccent,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                color: _deleteAccent,
                                size: 22.0,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10.0),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildBadge(
                        context,
                        icon: Icons.calendar_today_rounded,
                        label: winDateLabel,
                        backgroundColor: _logoBlueTint,
                        textColor: _logoBlue,
                      ),
                      const SizedBox(width: 8.0),
                      _buildBadge(
                        context,
                        icon: claimed
                            ? Icons.check_circle_outline_rounded
                            : Icons.schedule_rounded,
                        label: claimed ? 'Réclamé' : 'Non réclamé',
                        backgroundColor:
                            claimed ? _logoBlueTint : _logoOrangeTint,
                        textColor:
                            claimed ? _logoBlue : const Color(0xFFE97443),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
