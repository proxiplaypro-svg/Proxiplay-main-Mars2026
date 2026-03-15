import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileMenuCard extends StatelessWidget {
  const ProfileMenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    required this.iconTint,
    required this.iconColor,
    required this.titleColor,
    required this.borderColor,
    required this.shadowColor,
    this.compactLabel = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color iconTint;
  final Color iconColor;
  final Color titleColor;
  final Color borderColor;
  final Color shadowColor;
  final bool compactLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 16.0,
              offset: const Offset(0.0, 8.0),
            ),
          ],
        ),
        child: Padding(
          padding:
              const EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 16.0),
          child: Row(
            children: [
              Container(
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: iconTint,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18.0,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      14.0, 0.0, 12.0, 0.0),
                  child: Text(
                    title,
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight:
                                compactLabel ? FontWeight.w600 : FontWeight.w700,
                            fontStyle:
                                FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                          ),
                          color: titleColor,
                          fontSize: compactLabel ? 15.0 : 16.0,
                          letterSpacing: 0.0,
                          fontWeight:
                              compactLabel ? FontWeight.w600 : FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
