import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/services/ad_system_service.dart';
import '/utils/ad_system_utils.dart';

/// Home advertising banner (sold directly by ProxiPlay, not AdMob).
///
/// - Nothing at all (no margin) when no ad can be shown, or if its image
///   fails to load.
/// - No sudden jump: the space appears and disappears with a short size
///   animation, and is reserved as soon as an ad is known to be shown, while
///   its image loads behind a neutral placeholder.
/// - An impression is counted only once the image is displayed and at least
///   half of the banner has stayed on screen for one second, app in the
///   foreground. A refresh showing the same campaign does not count it again
///   (the server also ignores repeats within its exposure window).
class AdBannerZone extends StatefulWidget {
  const AdBannerZone({
    super.key,
    required this.placement,
    required this.configFuture,
    required this.service,
    this.trailingSpace = 0.0,
    this.minVisibleFraction = 0.5,
    this.minVisibleDuration = const Duration(seconds: 1),
    @visibleForTesting this.imageProviderFor,
  });

  final String placement;
  final Future<AdPlacementConfig?> configFuture;
  final AdSystemService service;
  final double trailingSpace;
  final double minVisibleFraction;
  final Duration minVisibleDuration;
  final ImageProvider Function(String url)? imageProviderFor;

  static const double bannerHeight = 90.0;

  @override
  State<AdBannerZone> createState() => _AdBannerZoneState();
}

class _AdBannerZoneState extends State<AdBannerZone>
    with WidgetsBindingObserver {
  AdPlacementConfig? _config;
  bool _imageShown = false;
  bool _imageFailed = false;
  // Campaigns already counted by this banner: a refresh of the same
  // campaign is not a new exposure.
  final Set<String> _countedCampaigns = <String>{};
  Timer? _dwellTimer;
  // Re-checks visibility while an impression is pending: the banner can come
  // into view without any scroll (size animation, content loading above).
  Timer? _pollTimer;
  ScrollPosition? _scrollPosition;
  int _loadGeneration = 0;

  ImageProvider _image(String url) =>
      widget.imageProviderFor?.call(url) ?? NetworkImage(url);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant AdBannerZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configFuture != widget.configFuture) _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_checkVisibility);
      _scrollPosition = position;
      _scrollPosition?.addListener(_checkVisibility);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_checkVisibility);
    _dwellTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVisibility();
    } else {
      _dwellTimer?.cancel();
      _dwellTimer = null;
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    AdPlacementConfig? config;
    try {
      config = await widget.configFuture;
    } catch (_) {
      config = null;
    }
    if (!mounted || generation != _loadGeneration) return;
    final eligible = config != null &&
        isAdPlacementEnabled(
          enabled: config.enabled,
          startAt: config.startAt,
          endAt: config.endAt,
          now: DateTime.now(),
        ) &&
        config.hasUsableCreative;
    final keepImage =
        eligible && _config?.imageUrl == config.imageUrl && _imageShown;
    _dwellTimer?.cancel();
    _dwellTimer = null;
    setState(() {
      _config = eligible ? config : null;
      _imageShown = keepImage;
      _imageFailed = false;
    });
    if (keepImage) _scheduleVisibilityCheck();
  }

  void _onImageShown() {
    if (_imageShown || !mounted) return;
    setState(() => _imageShown = true);
    _scheduleVisibilityCheck();
  }

  void _onImageFailed() {
    if (_imageFailed || !mounted) return;
    _dwellTimer?.cancel();
    _dwellTimer = null;
    setState(() => _imageFailed = true);
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      final config = _config;
      if (!mounted ||
          config == null ||
          _imageFailed ||
          _countedCampaigns.contains(config.campaignId)) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      _checkVisibility();
    });
  }

  /// Fraction of the banner visible on screen (and inside its scroll view).
  double _visibleFraction() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) {
      return 0.0;
    }
    var visible = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    visible = visible.intersect(screen);
    final scrollBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (scrollBox is RenderBox && scrollBox.attached && scrollBox.hasSize) {
      visible = visible
          .intersect(scrollBox.localToGlobal(Offset.zero) & scrollBox.size);
    }
    if (visible.width <= 0 || visible.height <= 0) return 0.0;
    final area = box.size.width * box.size.height;
    return math.min(1.0, (visible.width * visible.height) / area);
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _checkVisibility() {
    final config = _config;
    if (!mounted ||
        config == null ||
        !_imageShown ||
        _imageFailed ||
        _countedCampaigns.contains(config.campaignId)) {
      return;
    }
    final visibleEnough =
        _foreground && _visibleFraction() >= widget.minVisibleFraction;
    if (!visibleEnough) {
      _dwellTimer?.cancel();
      _dwellTimer = null;
      return;
    }
    _dwellTimer ??= Timer(widget.minVisibleDuration, () {
      _dwellTimer = null;
      final current = _config;
      if (!mounted ||
          current == null ||
          current.campaignId != config.campaignId ||
          !_foreground ||
          _visibleFraction() < widget.minVisibleFraction) {
        return;
      }
      if (_countedCampaigns.add(current.campaignId)) {
        unawaited(widget.service.recordImpression(widget.placement,
            campaignId: current.campaignId));
      }
    });
  }

  Future<void> _onTap(AdPlacementConfig config) async {
    if (config.destinationUrl.isEmpty) return;
    unawaited(widget.service
        .recordClick(widget.placement, campaignId: config.campaignId));
    try {
      await launchURL(config.destinationUrl);
    } catch (_) {
      // Une destination mal configuree ne doit jamais faire planter la Home.
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final show = config != null && !_imageFailed;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity, height: 0.0)
          : Padding(
              key: ValueKey('ad-banner-${widget.placement}'),
              padding: EdgeInsets.only(top: 16.0, bottom: widget.trailingSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nature of the communication, above the banner so it never
                  // hides the image ("Publicité", "À découvrir", "Info ProxiPlay").
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: 4.0, bottom: 4.0),
                    child: Text(
                      config.communicationLabel,
                      key: ValueKey('ad-banner-label-${widget.placement}'),
                      style: const TextStyle(
                        color: Color(0xFF6F6A8E),
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  _bannerImage(config),
                ],
              ),
            ),
    );
  }

  Widget _bannerImage(AdPlacementConfig config) {
    return SizedBox(
      width: double.infinity,
      height: AdBannerZone.bannerHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Neutral placeholder while the image loads.
            const ColoredBox(color: Color(0xFFF1F2F6)),
            InkWell(
              onTap: () => _onTap(config),
              child: Image(
                image: _image(config.imageUrl),
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame != null || wasSynchronouslyLoaded) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _onImageShown());
                  }
                  return AnimatedOpacity(
                    opacity:
                        frame != null || wasSynchronouslyLoaded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _onImageFailed());
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
