import 'package:flutter/material.dart';

class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.asset,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final String asset;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(asset, fit: fit),
    );
  }
}
