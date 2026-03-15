import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommercantsAdminPlaceholderPageWidget extends StatelessWidget {
  const CommercantsAdminPlaceholderPageWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        title: Text(
          'Commercants',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleLarge.fontStyle,
            ),
            letterSpacing: 0.0,
            fontWeight: FontWeight.w700,
            fontStyle: theme.titleLarge.fontStyle,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Fonction a venir',
            style: theme.headlineSmall.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.headlineSmall.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
              fontStyle: theme.headlineSmall.fontStyle,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
