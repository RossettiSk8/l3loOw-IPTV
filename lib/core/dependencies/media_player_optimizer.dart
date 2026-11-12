import 'dart:math' as math;

import 'package:video_player/video_player.dart';

import '../../domain/entities/stream_option.dart';

abstract final class MediaPlayerOptimizer {
  static VideoPlayerController createController(
    StreamOption source,
  ) => VideoPlayerController.networkUrl(
    source.url,
    formatHint: switch (source.delivery) {
      StreamDelivery.hls => VideoFormat.hls,
      StreamDelivery.dash => VideoFormat.dash,
      StreamDelivery.progressive => null,
    },
    videoPlayerOptions: VideoPlayerOptions(
      // El servicio de energía gestiona la pausa y evita el autoarranque del plugin.
      allowBackgroundPlayback: true,
      preventsDisplaySleepDuringVideoPlayback: false,
    ),
  );

  static ({int width, int height}) imageDecodeSize({
    required double logicalWidth,
    required double logicalHeight,
    required double pixelRatio,
    required bool panorama,
  }) {
    final aspect = panorama ? 16 / 9 : 2 / 3;
    final maxWidth = panorama ? 1920 : 768;
    final maxHeight = panorama ? 1080 : 1152;
    final width = logicalWidth.isFinite ? logicalWidth : 0.0;
    final height = logicalHeight.isFinite ? logicalHeight : 0.0;
    final targetWidth = math.max(width, height * aspect) * pixelRatio;
    // Agrupa tamaños cercanos para reutilizar la misma entrada de caché.
    final scaled = targetWidth.clamp(128.0, maxWidth.toDouble());
    final decodeWidth = math.min(maxWidth, (scaled / 64).ceil() * 64);
    return (
      width: decodeWidth,
      height: math.min(maxHeight, (decodeWidth / aspect).round()),
    );
  }
}
