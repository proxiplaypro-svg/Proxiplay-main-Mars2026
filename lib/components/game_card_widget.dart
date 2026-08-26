import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/backend/schema/enums/enums.dart';
import '/widgets/proxiplay_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GameCard extends StatefulWidget {
  const GameCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.storeName,
    required this.city,
    required this.prizeText,
    required this.endDateText,
    this.badgeText,
    this.winnerText,
    this.gameAccessType,
    this.accessMode,
    this.width,
    this.height,
    this.imageHeight,
    this.onTap,
    this.desaturateImage = false,
    this.fitContent = true,
    this.winnerMaxLines = 1,
    this.isFinished = false,
    this.finishedInfoText = 'Jeu termin\u00E9',
  });

  final String title;
  final String imageUrl;
  final String storeName;
  final String city;
  final String prizeText;
  final String endDateText;
  final String? badgeText;
  final String? winnerText;
  final GameAccessType? gameAccessType;
  final AccessMode? accessMode;
  final double? width;
  final double? height;
  final double? imageHeight;
  final VoidCallback? onTap;
  final bool desaturateImage;
  final bool fitContent;
  final int winnerMaxLines;
  final bool isFinished;
  final String finishedInfoText;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  static const _pressDuration = Duration(milliseconds: 180);
  static const _tapDelay = Duration(milliseconds: 150);

  bool _isPressed = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    if (!_isPressed) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (widget.onTap == null) return;
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  Future<void> _handleTap() async {
    final onTap = widget.onTap;
    if (onTap == null) return;
    await Future.delayed(_tapDelay);
    if (!mounted) return;
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final effectiveDesaturate = widget.desaturateImage || widget.isFinished;
    final effectiveBadge =
        widget.badgeText ?? (widget.isFinished ? 'Jeu termin\u00E9' : null);
    final ribbon = _buildAccessRibbon();
    final hasPrize = _hasVisibleText(widget.prizeText);
    final responsiveWidth = (screenWidth * 0.58).clamp(188.0, 248.0);
    final computedWidth = widget.width ?? responsiveWidth;
    final responsiveImageHeight = (computedWidth * 0.50).clamp(84.0, 116.0);
    final effectiveImageHeight = widget.imageHeight ??
        (widget.isFinished
            ? AppStyles.finishedGameImageHeight
            : responsiveImageHeight);
    final baseHeight = widget.isFinished
        ? AppStyles.finishedGameListHeight
        : AppStyles.gameCardHeight;
    final effectiveHeight = widget.fitContent
        ? widget.height
        : (widget.height ??
            (baseHeight +
                ((widget.width == double.infinity && !widget.isFinished)
                    ? 8.0
                    : 0.0)));
    final cardRadius = BorderRadius.circular(AppStyles.gameCardRadius);

    final cardBody = Stack(
      children: [
        Column(
          mainAxisSize:
              effectiveHeight == null ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: effectiveImageHeight,
              child: effectiveDesaturate
                  ? ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.grey.withValues(alpha: 0.9),
                        BlendMode.saturation,
                      ),
                      child: ProxiplayNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.cover,
                      ),
                    )
                  : ProxiplayNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.cover,
                    ),
            ),
            if (effectiveHeight == null)
              _buildContent(context)
            else
              Expanded(
                child: _buildContent(context),
              ),
          ],
        ),
        if (effectiveBadge != null && effectiveBadge.isNotEmpty)
          Positioned(
            left: 0.0,
            top: 0.0,
            child: Container(
              padding: AppStyles.gameCardBadgePadding,
              decoration: const BoxDecoration(
                color: AppStyles.gameCardBadgeColor,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(18.0),
                ),
              ),
              child: Text(
                _normalizeText(effectiveBadge),
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: Colors.white,
                      fontSize: AppStyles.gameCardBadgeSize,
                      letterSpacing: 0.0,
                    ),
              ),
            ),
          ),
        if (ribbon != null)
          Positioned(
            top: 10.0,
            right: 10.0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: ribbon.backgroundColor,
                borderRadius: BorderRadius.circular(999.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 8.0,
                    offset: const Offset(0.0, 2.0),
                  ),
                ],
              ),
              child: Text(
                ribbon.label,
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: ribbon.textColor,
                      fontSize: 11.0,
                      letterSpacing: 0.0,
                    ),
              ),
            ),
          ),
        if (hasPrize)
          Positioned(
            left: 8.0,
            top: effectiveImageHeight - 16.0,
            child: Container(
              padding: AppStyles.gameCardPriceBadgePadding,
              decoration: BoxDecoration(
                color: AppStyles.gameCardPriceBadgeColor,
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8.0,
                    offset: const Offset(0.0, 2.0),
                  ),
                ],
              ),
              child: Text(
                _formatPriceText(widget.prizeText),
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: Colors.white,
                      fontSize: AppStyles.gameCardPriceBadgeSize,
                      letterSpacing: 0.0,
                    ),
              ),
            ),
          ),
      ],
    );

    final animatedCard = AnimatedContainer(
        duration: _pressDuration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0.0, _isPressed ? 6.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          border: Border.all(
            color: _isPressed ? const Color(0xFFA0134D) : Colors.transparent,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isPressed ? 0.04 : 0.08),
              blurRadius: _isPressed ? 6.0 : 16.0,
              offset: Offset(0.0, _isPressed ? 2.0 : 6.0),
            ),
          ],
        ),
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : 1.0,
          duration: _pressDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _isPressed ? 0.85 : 1.0,
            duration: _pressDuration,
            curve: Curves.easeOutCubic,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: cardRadius,
                splashColor:
                    FlutterFlowTheme.of(context).primary.withValues(alpha: 0.20),
                highlightColor:
                    FlutterFlowTheme.of(context).primary.withValues(alpha: 0.10),
                onTapDown: widget.onTap != null ? _handleTapDown : null,
                onTapUp: widget.onTap != null ? _handleTapUp : null,
                onTapCancel: widget.onTap != null ? _handleTapCancel : null,
                onTap: widget.onTap != null ? _handleTap : null,
                child: ClipRRect(
                  borderRadius: cardRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.isFinished
                          ? Colors.white
                          : FlutterFlowTheme.of(context).secondaryBackground,
                    ),
                    child: cardBody,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

    if (effectiveHeight == null) {
      return SizedBox(
        width: computedWidth,
        child: Align(
          alignment: Alignment.topCenter,
          child: animatedCard,
        ),
      );
    }

    return SizedBox(
      width: computedWidth,
      height: effectiveHeight,
      child: animatedCard,
    );
  }

  Widget _buildContent(BuildContext context) {
    final effectiveWinnerMaxLines = widget.isFinished ? 2 : widget.winnerMaxLines;
    final rowSpacing = widget.isFinished ? 6.0 : 4.0;
    final hasPrize = _hasVisibleText(widget.prizeText);
    final hasCity = _hasVisibleText(widget.city);
    final titleTopSpacing = hasPrize ? 8.0 : 0.0;
    final contentPadding = (!widget.isFinished && hasPrize)
        ? const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 4.0)
        : AppStyles.gameCardContentPadding;
    return Container(
      color: widget.isFinished ? Colors.white : Colors.transparent,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titleTopSpacing > 0.0) SizedBox(height: titleTopSpacing),
            Text(
              _normalizeText(widget.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    fontSize: AppStyles.gameCardTitleSize,
                    color: Colors.black,
                    letterSpacing: 0.0,
                  ),
            ),
            SizedBox(height: rowSpacing),
            _infoRow(
              Icons.storefront_outlined,
              widget.storeName,
              context,
              fontWeight: FontWeight.w700,
            ),
            if (hasCity) ...[
              SizedBox(height: rowSpacing),
              _infoRow(Icons.location_on_outlined, widget.city, context),
            ],
            SizedBox(height: rowSpacing),
            _infoRow(Icons.calendar_today_outlined, widget.endDateText, context),
            if (widget.isFinished &&
                (widget.winnerText == null || widget.winnerText!.isEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 3.0),
                child:
                    _infoRow(Icons.info_outline, widget.finishedInfoText, context),
              ),
            if (widget.winnerText != null && widget.winnerText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppStyles.gameCardWinnerBackground,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  padding: AppStyles.gameCardWinnerPadding,
                  child: Text(
                    _normalizeText(widget.winnerText!),
                    maxLines: effectiveWinnerMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodySmall
                                .fontStyle,
                          ),
                          color: AppStyles.gameCardWinnerText,
                          letterSpacing: 0.0,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String text,
    BuildContext context, {
    FontWeight? fontWeight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.0),
          child: Icon(icon, size: 18.0, color: const Color(0xFF26235C)),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            _normalizeText(text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight:
                        fontWeight ??
                            FlutterFlowTheme.of(context).bodySmall.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  color: const Color(0xFF26235C),
                  fontSize: AppStyles.gameCardBodySize,
                  letterSpacing: 0.0,
                ),
          ),
        ),
      ],
    );
  }

  bool _hasVisibleText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  _GameCardRibbonData? _buildAccessRibbon() {
    if (widget.accessMode != AccessMode.qr_only) {
      return null;
    }

    switch (widget.gameAccessType) {
      case GameAccessType.campaign:
        return const _GameCardRibbonData(
          label: 'En commerce',
          backgroundColor: Color(0xFFF59E0B),
          textColor: Colors.white,
        );
      case GameAccessType.loyalty:
        return const _GameCardRibbonData(
          label: 'VIP',
          backgroundColor: Color(0xFF6D28D9),
          textColor: Colors.white,
        );
      case GameAccessType.standard:
      case null:
        return null;
    }
  }

  String _formatPriceText(String value) {
    final normalized = _normalizeText(value).trim();
    final match =
        RegExp(r'^(\d+)(?:[.,](\d{1,2}))?\s*€?$').firstMatch(normalized);
    if (match == null) {
      return normalized;
    }
    final euros = match.group(1)!;
    final decimals = match.group(2);
    if (decimals == null || int.tryParse(decimals) == 0) {
      return '$euros €';
    }
    final trimmedDecimals = decimals.replaceFirst(RegExp(r'0+$'), '');
    return '$euros,$trimmedDecimals €';
  }

  String _normalizeText(String value) {
    return value
        .replaceAll('Ã¢â€šÂ¬', '\u20AC')
        .replaceAll('ÃƒÂ©', '\u00E9')
        .replaceAll('ÃƒÂ¨', '\u00E8')
        .replaceAll('ÃƒÂª', '\u00EA')
        .replaceAll('ÃƒÂ«', '\u00EB')
        .replaceAll('ÃƒÂ ', '\u00E0')
        .replaceAll('ÃƒÂ¢', '\u00E2')
        .replaceAll('ÃƒÂ¹', '\u00F9')
        .replaceAll('ÃƒÂ»', '\u00FB')
        .replaceAll('ÃƒÂ´', '\u00F4')
        .replaceAll('ÃƒÂ®', '\u00EE')
        .replaceAll('ÃƒÂ¯', '\u00EF')
        .replaceAll('Ãƒâ€¡', '\u00C7')
        .replaceAll('ÃƒÂ§', '\u00E7')
        .replaceAll('Ãƒâ‚¬', '\u00C0')
        .replaceAll('Ãƒâ€°', '\u00C9')
        .replaceAll('Ãƒâ€', '\u00D4')
        .replaceAll('Ã¢â‚¬â„¢', '\'')
        .replaceAll('\uFFFD', '');
  }
}

class GameCardWidget extends GameCard {
  const GameCardWidget({
    super.key,
    required super.title,
    required super.imageUrl,
    required super.storeName,
    required super.city,
    required super.prizeText,
    required super.endDateText,
    super.badgeText,
    super.winnerText,
    super.gameAccessType,
    super.accessMode,
    super.width,
    super.height,
    super.imageHeight,
    super.onTap,
    super.desaturateImage,
    super.fitContent,
    super.winnerMaxLines,
    super.isFinished,
    super.finishedInfoText,
  });
}

class _GameCardRibbonData {
  const _GameCardRibbonData({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
}
