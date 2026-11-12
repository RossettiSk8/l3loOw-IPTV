// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/dependencies/media_player_optimizer.dart';
import 'streaming_theme.dart';

class CatalogImage extends StatelessWidget {
  const CatalogImage({
    required this.uri,
    this.alignment = Alignment.center,
    this.panorama = false,
    super.key,
  });

  final Uri? uri;
  final Alignment alignment;
  final bool panorama;

  @override
  Widget build(BuildContext context) {
    final image = uri;
    const fallback = ColoredBox(
      color: StreamingPalette.surface,
      child: Center(
        child: Icon(Icons.movie_outlined, color: StreamingPalette.muted),
      ),
    );
    if (image == null) return fallback;
    final ImageProvider provider = image.scheme == 'asset'
        ? AssetImage(image.path)
        : NetworkImage(image.toString());
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = MediaPlayerOptimizer.imageDecodeSize(
          logicalWidth: constraints.maxWidth,
          logicalHeight: constraints.maxHeight,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          panorama: panorama,
        );
        return Image(
          image: ResizeImage(
            provider,
            width: target.width,
            height: target.height,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.cover,
          alignment: alignment,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}
