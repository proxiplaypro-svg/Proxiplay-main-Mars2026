import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum SharePromoKind {
  rewardAvailable,
  friendPending,
  specialCampaign,
  lowRemainingPlaysInvite,
  defaultInvite,
}

class SharePromoData {
  const SharePromoData({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    this.ctaLabel,
    this.titleColor,
    this.subtitleColor,
    this.buttonColor,
    this.buttonTextColor,
    this.iconBackgroundColor,
    this.iconColor,
  });

  final SharePromoKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final String? ctaLabel;
  final Color? titleColor;
  final Color? subtitleColor;
  final Color? buttonColor;
  final Color? buttonTextColor;
  final Color? iconBackgroundColor;
  final Color? iconColor;
}

class SharePromoBanner extends StatelessWidget {
  const SharePromoBanner({
    super.key,
    required this.data,
    this.onTap,
  });

  final SharePromoData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final titleColor = data.titleColor ?? const Color(0xFF2C2F5B);
    final subtitleColor =
        data.subtitleColor ?? const Color(0xFF2C2F5B).withValues(alpha: 0.78);
    final accentColor = data.secondaryColor;
    final buttonColor = data.buttonColor ?? accentColor;
    final buttonTextColor = data.buttonTextColor ?? Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: data.primaryColor,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.14),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C2F5B).withValues(alpha: 0.06),
                blurRadius: 14.0,
                offset: const Offset(0.0, 6.0),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactButton = constraints.maxWidth < 390.0;

              Widget ctaButton() => Container(
                    constraints: BoxConstraints(
                      minWidth: compactButton ? 122.0 : 142.0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      data.ctaLabel!,
                      textAlign: TextAlign.center,
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                        color: buttonTextColor,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                        fontStyle: theme.bodySmall.fontStyle,
                      ),
                    ),
                  );

              return Container(
                constraints: const BoxConstraints(minHeight: 60.0),
                padding:
                    const EdgeInsetsDirectional.fromSTEB(14.0, 12.0, 14.0, 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: data.iconBackgroundColor ??
                            accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                      child: Icon(
                        data.icon,
                        color: data.iconColor ?? accentColor,
                        size: 22.0,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  data.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: theme.titleMedium.fontStyle,
                                    ),
                                    color: titleColor,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: theme.titleMedium.fontStyle,
                                  ),
                                ),
                              ),
                              if (data.ctaLabel != null) ...[
                                const SizedBox(width: 12.0),
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: ctaButton(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            data.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontStyle: theme.bodySmall.fontStyle,
                              ),
                              color: subtitleColor,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w500,
                              fontStyle: theme.bodySmall.fontStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
