import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TapHaptic { none, light, medium }

class TapFeedback extends StatefulWidget {
  const TapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.haptic = TapHaptic.light,
    this.scalePressed = 0.96,
    this.duration = const Duration(milliseconds: 110),
    this.borderRadius,
    this.pressedOpacity = 0.98,
    this.boxShadow,
    this.pressedBoxShadow,
    this.splashColor,
    this.highlightColor,
    this.pressOffset = Offset.zero,
    this.tapDelay = Duration.zero,
    this.border,
    this.pressedBorder,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final TapHaptic haptic;
  final double scalePressed;
  final Duration duration;
  final BorderRadius? borderRadius;
  final double pressedOpacity;
  final List<BoxShadow>? boxShadow;
  final List<BoxShadow>? pressedBoxShadow;
  final Color? splashColor;
  final Color? highlightColor;
  final Offset pressOffset;
  final Duration tapDelay;
  final BoxBorder? border;
  final BoxBorder? pressedBorder;

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _pressed = false;

  bool get _canHandle =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  bool get _supportsHaptics {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  Future<void> _triggerHaptic() async {
    if (!_supportsHaptics || widget.haptic == TapHaptic.none) return;
    try {
      if (widget.haptic == TapHaptic.medium) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  void _handleTapDown(TapDownDetails _) {
    if (!_canHandle) return;
    if (!_pressed) {
      setState(() => _pressed = true);
    }
    _triggerHaptic();
  }

  void _handleTapUp(TapUpDetails _) {
    if (!_canHandle) return;
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }

  void _handleTapCancel() {
    if (!_canHandle) return;
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }

  Future<void> _handleTap() async {
    if (!_canHandle || widget.onTap == null) return;
    if (widget.tapDelay > Duration.zero) {
      await Future.delayed(widget.tapDelay);
      if (!mounted) return;
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canHandle) {
      return widget.child;
    }

    final borderRadius = widget.borderRadius ?? BorderRadius.zero;
    final child = AnimatedContainer(
      duration: widget.duration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: _pressed ? (widget.pressedBorder ?? widget.border) : widget.border,
        boxShadow: _pressed
            ? (widget.pressedBoxShadow ?? widget.boxShadow)
            : widget.boxShadow,
      ),
      transform: Matrix4.translationValues(
        _pressed ? widget.pressOffset.dx : 0.0,
        _pressed ? widget.pressOffset.dy : 0.0,
        0.0,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            AnimatedScale(
              scale: _pressed ? widget.scalePressed : 1.0,
              duration: widget.duration,
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _pressed ? widget.pressedOpacity : 1.0,
                duration: widget.duration,
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: borderRadius,
                  splashColor: widget.splashColor,
                  highlightColor: widget.highlightColor,
                  onTapDown: _canHandle ? _handleTapDown : null,
                  onTapUp: _canHandle ? _handleTapUp : null,
                  onTapCancel: _canHandle ? _handleTapCancel : null,
                  onTap: _canHandle ? _handleTap : null,
                  onLongPress: _canHandle ? widget.onLongPress : null,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return child;
  }
}
