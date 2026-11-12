import '../entities/stream_option.dart';

enum QualityMode { automatic, manual }

List<StreamOption> manualQualityOptions(Iterable<StreamOption> sources) {
  final ranked =
      sources
          .where((source) => source.isPlayable && !source.isAdaptive)
          .indexed
          .toList()
        ..sort((left, right) {
          final height = (right.$2.height ?? 0).compareTo(left.$2.height ?? 0);
          return height == 0 ? left.$1.compareTo(right.$1) : height;
        });
  return [for (final entry in ranked) entry.$2];
}

List<StreamOption> progressiveVariants(
  StreamOption current,
  Iterable<StreamOption> sources,
) {
  final group = current.variantGroup;
  if (group == null || current.isAdaptive || current.height == null) {
    return const [];
  }
  return [
    for (final source in manualQualityOptions(sources))
      if (source.providerId == current.providerId &&
          source.variantGroup == group &&
          source.height != null)
        source,
  ];
}

/// Estima el rendimiento a partir del avance del búfer, sin descargar muestras.
final class ProgressiveQualityPolicy {
  Duration? _started;
  Duration? _sampleTime;
  Duration? _sampleEnd;
  Duration? _badSince;
  Duration? _healthySince;
  Duration? _lastDownload;
  double? _throughput;

  void reset() {
    _started = null;
    _sampleTime = null;
    _sampleEnd = null;
    _badSince = null;
    _healthySince = null;
    _lastDownload = null;
    _throughput = null;
  }

  StreamOption? sample({
    required StreamOption current,
    required List<StreamOption> variants,
    required Duration now,
    required Duration position,
    required Duration bufferedUntil,
    required Duration duration,
    required bool isBuffering,
  }) {
    final height = current.height;
    if (height == null || duration <= Duration.zero) return null;
    final remaining = duration - position;
    if (remaining <= const Duration(seconds: 6)) return null;

    final started = _started ??= now;
    final previousTime = _sampleTime;
    final previousEnd = _sampleEnd;
    _sampleTime = now;
    _sampleEnd = bufferedUntil;
    if (previousTime != null && previousEnd != null) {
      final downloaded = (bufferedUntil - previousEnd).inMilliseconds;
      final elapsed = (now - previousTime).inMilliseconds;
      if (downloaded > 0 && elapsed > 0 && !isBuffering) {
        final estimate = _bitrate(current, duration) * downloaded / elapsed;
        _throughput = _throughput == null
            ? estimate
            : _throughput! * .7 + estimate * .3;
        _lastDownload = now;
      }
    }

    final buffer = bufferedUntil - position;
    final bad = isBuffering || buffer <= const Duration(seconds: 2);
    final healthy = !isBuffering && buffer >= const Duration(seconds: 14);
    _badSince = bad ? _badSince ?? now : null;
    _healthySince = healthy ? _healthySince ?? now : null;
    if (now - started < const Duration(seconds: 6)) return null;

    final badSince = _badSince;
    if (badSince != null && now - badSince >= const Duration(seconds: 4)) {
      // Las variantes llegan ordenadas de mayor a menor resolución.
      return variants
          .where((source) => (source.height ?? 0) < height)
          .firstOrNull;
    }
    final healthySince = _healthySince;
    final download = _lastDownload;
    final throughput = _throughput;
    if (healthySince != null &&
        now - healthySince >= const Duration(seconds: 12) &&
        download != null &&
        now - download <= const Duration(seconds: 8) &&
        throughput != null) {
      return variants.reversed.where((source) {
        return (source.height ?? 0) > height &&
            throughput >= _bitrate(source, duration) * 1.3;
      }).firstOrNull;
    }
    return null;
  }

  double _bitrate(StreamOption source, Duration duration) {
    final bitrate = source.bitrate;
    if (bitrate != null && bitrate > 0) return bitrate.toDouble();
    final size = source.size;
    if (size != null && size > 0) return size * 8000 / duration.inMilliseconds;
    final height = source.height ?? 720;
    return height * height * 4.0;
  }
}
