import 'subtitle_track.dart';
import 'video_resolution.dart';

enum StreamDelivery { progressive, hls, dash }

final class StreamOption {
  const StreamOption({
    required this.quality,
    required this.url,
    required this.providerId,
    this.size,
    this.seeders,
    this.sourceName,
    this.torrentFileIndex,
    this.subtitles = const [],
    this.videoHeight,
    this.bitrate,
    this.variantGroup,
    this.deliveryHint,
  });

  final String quality;
  final Uri url;
  final String providerId;

  /// Tamaño en bytes, cuando el proveedor lo informa.
  final int? size;

  /// Semillas anunciadas por el complemento. Ausencia de dato y cero son distintos.
  final int? seeders;
  final String? sourceName;

  /// Índice dentro de una referencia BitTorrent, si el complemento lo indica.
  final int? torrentFileIndex;
  final List<SubtitleTrack> subtitles;
  final int? videoHeight;

  /// Tasa de bits de video en bits por segundo, si el complemento la indica.
  final int? bitrate;

  /// Identifica variantes del mismo montaje dentro de un complemento.
  final String? variantGroup;
  final StreamDelivery? deliveryHint;

  int? get height =>
      parseVideoHeight(videoHeight) ??
      parseVideoHeight(quality, allowBareHeight: true);

  String get qualityLabel => switch (height) {
    _ when isAdaptive => 'Adaptativa',
    final int height => formatVideoHeight(height),
    _ when quality.trim().isEmpty || quality.toLowerCase() == 'auto' =>
      'Sin resolución indicada',
    _ => quality,
  };

  StreamDelivery get delivery {
    final hint = deliveryHint;
    if (hint != null) return hint;
    final path = url.path.toLowerCase();
    if (path.endsWith('.m3u8')) return StreamDelivery.hls;
    if (path.endsWith('.mpd')) return StreamDelivery.dash;
    return StreamDelivery.progressive;
  }

  bool get isAdaptive => delivery != StreamDelivery.progressive;

  bool get isPlayable =>
      (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;
}
