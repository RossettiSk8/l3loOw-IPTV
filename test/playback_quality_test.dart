import 'package:app_streaming/domain/entities/stream_option.dart';
import 'package:app_streaming/domain/entities/video_resolution.dart';
import 'package:app_streaming/domain/repositories/playback_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Normaliza y ordena resoluciones sin deducirlas de un año o de HD', () {
    final sources = [
      _source('480p'),
      _source('UHD'),
      _source('720P'),
      _source('1920×1080'),
      _source('8K'),
      _source('1080p', file: 'segunda-opcion'),
      _source('HD'),
      _source('720p', file: 'playlist.m3u8'),
    ];
    expect(manualQualityOptions(sources).map((source) => source.qualityLabel), [
      '8K',
      '4K',
      '1080p',
      '1080p',
      '720p',
      '480p',
      'HD',
    ]);
    expect(manualQualityOptions(sources)[2], same(sources[3]));
    expect(parseVideoHeight('Película de 2024'), isNull);
    expect(parseVideoHeight('1440', allowBareHeight: true), 1440);
    expect(sources.last.delivery, StreamDelivery.hls);
  });

  test('Agrupa únicamente enlaces fijos del mismo montaje y proveedor', () {
    final selected = _source('1080p');
    final lower = _source('720p');
    final others = [
      _source('480p', group: 'otro'),
      _source('4K', provider: 'otro'),
      _source('8K', file: 'master.mpd'),
    ];
    expect(progressiveVariants(selected, [lower, ...others, selected]), [
      selected,
      lower,
    ]);
    expect(
      progressiveVariants(_source('720p', group: null), [lower, selected]),
      isEmpty,
    );
  });

  test(
    'Baja ante un bloqueo sostenido y sube solo con red y búfer suficientes',
    () {
      final lower = _source('720p', bitrate: 1000000);
      final higher = _source('1080p', bitrate: 2000000);
      final variants = [higher, lower];
      final policy = ProgressiveQualityPolicy();
      StreamOption? sample(
        StreamOption source,
        int time,
        int position,
        int end, {
        bool stalling = false,
      }) {
        return policy.sample(
          current: source,
          variants: variants,
          now: Duration(seconds: time),
          position: Duration(seconds: position),
          bufferedUntil: Duration(seconds: end),
          duration: const Duration(minutes: 2),
          isBuffering: stalling,
        );
      }

      expect(sample(higher, 0, 24, 24, stalling: true), isNull);
      expect(sample(higher, 2, 24, 24, stalling: true), isNull);
      expect(sample(higher, 4, 24, 24, stalling: true), isNull);
      expect(sample(higher, 6, 24, 24, stalling: true), same(lower));

      policy.reset();
      for (var second = 0; second <= 12; second += 2) {
        expect(sample(lower, second, second, second + 16), isNull);
      }
      policy.reset();
      for (var second = 0; second < 12; second += 2) {
        expect(sample(lower, second, second, 16 + second * 3), isNull);
      }
      expect(sample(lower, 12, 12, 52), same(higher));
    },
  );
}

StreamOption _source(
  String quality, {
  String? file,
  String? group = 'montaje',
  String provider = 'demo',
  int? bitrate,
}) => StreamOption(
  quality: quality,
  url: Uri.https('example.com', '/${file ?? '$quality.mp4'}'),
  providerId: provider,
  variantGroup: group,
  bitrate: bitrate,
);
