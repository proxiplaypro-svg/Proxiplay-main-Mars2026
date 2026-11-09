import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '/widgets/proxiplay_loading_logo.dart';

class ProxiplayNetworkImage extends StatelessWidget {
  const ProxiplayNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorBackgroundColor = const Color(0xFFE9EAF2),
    this.errorIconColor = const Color(0xFF6B70A7),
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color errorBackgroundColor;
  final Color errorIconColor;

  @override
  Widget build(BuildContext context) {
    Widget child = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 36.0,
          height: 36.0,
          child: ProxiplayLoadingLogo(size: 30.0),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: errorBackgroundColor,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: errorIconColor,
          size: 20.0,
        ),
      ),
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),
    );

    if (borderRadius != null) {
      child = ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }
    return child;
  }
}
