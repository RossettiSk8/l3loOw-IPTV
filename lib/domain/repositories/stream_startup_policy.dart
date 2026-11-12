import 'dart:math' as math;

import '../entities/stream_option.dart';
import '../entities/stream_request.dart';

/// Mantiene la prioridad del proveedor y ordena sus opciones para iniciar VOD.
List<StreamOption> rankStartupSources(
  Iterable<StreamOption> sources,
  StreamRequest request,
) {
  final runtime = request.media.runtimeMinutes;
  final minutes = runtime != null && runtime > 0
      ? runtime
      : (request.episode == null ? 105 : 45);
  final scored =
      [
        for (final (index, option) in sources.indexed)
          (option: option, score: _score(option, minutes), index: index),
      ]..sort((left, right) {
        final score = right.score.compareTo(left.score);
        return score == 0 ? left.index.compareTo(right.index) : score;
      });
  return [for (final entry in scored) entry.option];
}

double _score(StreamOption option, int minutes) {
  final seeds = option.seeders;
  // Los rendimientos decrecientes impiden que miles de semillas oculten un remux pesado.
  final availability = seeds == null || seeds <= 0
      ? 0.0
      : 8 * math.log(1 + math.min(seeds, 128));
  if (option.isAdaptive) return availability + 12;

  final height = option.height ?? 0;
  final (quality, targetMbps) = switch (height) {
    >= 2160 => (14.0, 13.0),
    >= 1440 => (13.0, 8.0),
    >= 1080 => (12.0, 5.8),
    >= 720 => (10.0, 3.3),
    >= 480 => (5.0, 1.8),
    _ => (4.0, 3.3),
  };
  final bitrate = option.bitrate;
  final size = option.size;
  final mbps = bitrate != null && bitrate > 0
      ? bitrate / 1000000
      : size != null && size > 0
      ? size * 8.0 / (minutes * 60 * 1000000)
      : 0.0;
  final relativeCost = 18 * math.log(math.max(1.0, mbps / targetMbps));
  final absoluteCost = 6 * math.log(math.max(1.0, mbps / 5));
  return availability + quality - relativeCost - absoluteCost;
}

final class StreamStartupPolicy {
  const StreamStartupPolicy();

  static const totalTimeout = Duration(seconds: 20);

  List<StreamOption> candidates(
    StreamOption source,
    Iterable<StreamOption> alternatives, {
    required bool automatic,
  }) {
    if (!automatic) return [source];
    final seen = {source.url};
    return [
      source,
      ...alternatives
          .where((item) => item.isPlayable && seen.add(item.url))
          .take(2),
    ];
  }

  Duration timeout(
    StreamOption source, {
    required Duration elapsed,
    required int remainingAlternatives,
  }) {
    final remaining = totalTimeout - elapsed;
    if (remaining <= Duration.zero) return Duration.zero;
    if (remainingAlternatives == 0) return remaining;
    final preferred = source.isAdaptive
        ? const Duration(seconds: 9)
        : const Duration(seconds: 6);
    final perCandidate = remaining ~/ (remainingAlternatives + 1);
    return perCandidate < preferred ? perCandidate : preferred;
  }
}
