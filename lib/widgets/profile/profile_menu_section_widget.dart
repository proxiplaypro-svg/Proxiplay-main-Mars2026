import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileMenuSection extends StatelessWidget {
  const ProfileMenuSection({
    super.key,
    required this.title,
    required this.titleColor,
    required this.children,
  });

  final String title;
  final Color titleColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(2.0, 0.0, 0.0, 0.0),
          child: Text(
            title,
            style: FlutterFlowTheme.of(context).labelLarge.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontStyle:
                        FlutterFlowTheme.of(context).labelLarge.fontStyle,
                  ),
                  color: titleColor,
                  fontSize: 14.0,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 12.0),
        ...children,
      ],
    );
  }
}
