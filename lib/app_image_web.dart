import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class AppImage extends StatefulWidget {
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
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  late final String viewType;

  @override
  void initState() {
    super.initState();
    viewType =
        'ssot-image-${DateTime.now().microsecondsSinceEpoch}-${widget.asset.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final radius = widget.borderRadius.topLeft.x;
      return html.ImageElement()
        ..src = 'assets/${widget.asset}'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = widget.fit == BoxFit.contain ? 'contain' : 'cover'
        ..style.objectPosition = 'center'
        ..style.borderRadius = radius > 0 ? '${radius}px' : '0'
        ..style.display = 'block';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: HtmlElementView(viewType: viewType),
    );
  }
}
