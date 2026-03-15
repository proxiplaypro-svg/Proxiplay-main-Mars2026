import 'package:flutter/material.dart';
class ProxiplayLoadingLogo extends StatefulWidget {
  const ProxiplayLoadingLogo({
    super.key,
    this.size = 42.0,
    this.duration = const Duration(milliseconds: 1200),
  });

  final double size;
  final Duration duration;

  @override
  State<ProxiplayLoadingLogo> createState() => _ProxiplayLoadingLogoState();
}

class _ProxiplayLoadingLogoState extends State<ProxiplayLoadingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        'assets/images/icon.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}
