import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shown in place of a signup button while its operation runs (account
/// creation, Google sign-in, profile saving): the player sees that the app is
/// working and cannot validate twice. The button comes back after a success
/// that keeps the page, or after a failure.
class SignupProgressIndicator extends StatelessWidget {
  const SignupProgressIndicator({
    super.key,
    required this.message,
    this.height = 52.0,
  });

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        key: const ValueKey('signup-progress'),
        width: double.infinity,
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: theme.primary,
              ),
            ),
            const SizedBox(width: 12.0),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.titleSmall.override(
                  font: GoogleFonts.interTight(),
                  color: theme.primaryText,
                  letterSpacing: 0.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
