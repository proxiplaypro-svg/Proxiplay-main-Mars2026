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
    this.animateCta = false,
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
  final bool animateCta;
}

class SharePromoBanner extends StatefulWidget {
  const SharePromoBanner({
    super.key,
    required this.data,
    this.onTap,
  });

  final SharePromoData data;
  final VoidCallback? onTap;

  @override
  State<SharePromoBanner> createState() => _SharePromoBannerState();
}

class _SharePromoBannerState extends State<SharePromoBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _ctaOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ctaOpacity = Tween<double>(begin: 1.0, end: 0.55).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.data.animateCta && widget.data.ctaLabel != null) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SharePromoBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate = widget.data.animateCta && widget.data.ctaLabel != null;
    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = FlutterFlowTheme.of(context);
    final hasTitle = data.title.trim().isNotEmpty;
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
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: data.primaryColor,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.14),
              width: 1.0,
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60.0),
            padding:
                const EdgeInsetsDirectional.fromSTEB(14.0, 10.0, 14.0, 10.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38.0,
                  height: 38.0,
                  decoration: BoxDecoration(
                    color: data.iconBackgroundColor ??
                        accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11.0),
                  ),
                  child: Icon(
                    data.icon,
                    color: data.iconColor ?? accentColor,
                    size: 18.0,
                  ),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasTitle)
                        Text(
                          data.title,
                          maxLines: 1,
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
                      if (hasTitle) const SizedBox(height: 4.0),
                      Text(
                        data.subtitle,
                        maxLines: hasTitle ? 2 : 3,
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
                if (data.ctaLabel != null) ...[
                  const SizedBox(width: 12.0),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: FadeTransition(
                      opacity: data.animateCta ? _ctaOpacity : kAlwaysCompleteAnimation,
                      child: Text(
                        data.ctaLabel!,
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
                    ),
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
