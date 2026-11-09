import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Compact empty state used by the two tabs of the player's Favorites page.
/// It deliberately has no imposed height, so it is safe in scrollables.
class FavoritesEmptyState extends StatelessWidget {
  const FavoritesEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.onDiscoverMerchants,
  });

  final String title;
  final String description;
  final VoidCallback? onDiscoverMerchants;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
        child: Card(
          key: const ValueKey('favorites-empty-card'),
          elevation: 0.0,
          color: theme.secondaryBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(color: theme.alternate),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border_rounded,
                    color: theme.secondaryText, size: 32.0),
                const SizedBox(height: 10.0),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.titleMedium.override(
                    font: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontStyle: theme.titleMedium.fontStyle,
                    ),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: theme.bodyMedium.fontWeight,
                      fontStyle: theme.bodyMedium.fontStyle,
                    ),
                    color: theme.secondaryText,
                    letterSpacing: 0.0,
                  ),
                ),
                if (onDiscoverMerchants != null) ...[
                  const SizedBox(height: 16.0),
                  FilledButton.icon(
                    key: const ValueKey('favorites-discover-merchants'),
                    onPressed: onDiscoverMerchants,
                    icon: const Icon(Icons.storefront_outlined, size: 18.0),
                    label: const Text('Découvrir les commerçants'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
