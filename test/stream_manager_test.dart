import 'package:app_streaming/core/network/http_transport.dart';
import 'package:app_streaming/data/adapters/torrentio_adapter.dart';
import 'package:app_streaming/data/network/json_api.dart';
import 'package:app_streaming/data/repositories/http_subtitle_repository.dart';
import 'package:app_streaming/data/streams/stream_manager.dart';
import 'package:app_streaming/domain/contracts/addon_repository.dart';
import 'package:app_streaming/domain/contracts/stream_provider_contract.dart';
import 'package:app_streaming/domain/entities/addon_entity.dart';
import 'package:app_streaming/domain/entities/media_item.dart';
import 'package:app_streaming/domain/entities/stream_option.dart';
import 'package:app_streaming/domain/entities/stream_request.dart';
import 'package:app_streaming/domain/entities/subtitle_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final request = StreamRequest.episode(
    const MediaItem(
      id: '42',
      kind: MediaKind.series,
      title: 'Serie de prueba',
      posterPath: null,
      overview: '',
    ),
    season: 2,
    episode: 3,
  );

  test('Aplica prioridad, exclusiones, deduplicación y respaldo', () async {
    final addons = _AddonSettings([
      _addon('fallback', 4),
      _addon('disabled', 1, enabled: false),
      _addon('torrentio', 3),
      _addon('error', 2),
    ]);
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('torrentio');
      expect(request.url.pathSegments, [
        'config',
        'stream',
        'series',
        'tt123:2:3.json',
      ]);
      return http.Response(
        '''
        {"streams":[
          {"infoHash":"fixture"},
          {"url":"https://example.com/headers","behaviorHints":{"proxyHeaders":{}}},
          {"url":"https://example.com/video","name":"1080p","behaviorHints":{"videoSize":123},
           "subtitles":[{"url":"/cc/es.vtt","lang":"spa","label":"Español"},
                        {"url":"https://example.com/cc/es.vtt","lang":"spa"},
                        {"url":"file:///test.srt","lang":"eng"}]}
        ]}
      ''',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);

    final manager = StreamManager(addons: addons)
      ..register('disabled', _Provider((_) => fail('Complemento desactivado')))
      ..register(
        'error',
        _Provider((_) {
          calls.add('error');
          throw const FormatException();
        }),
      )
      ..register(
        'torrentio',
        TorrentioAdapter(
          JsonApi(HttpTransport(client)),
          resolveImdbId: (media) async {
            expect(media.id, '42');
            return 'tt123';
          },
        ),
      )
      ..register(
        'fallback',
        _Provider((addon) {
          calls.add('fallback');
          return StreamOption(
            quality: 'Auto',
            url: Uri.parse('https://example.com/video'),
            providerId: addon.id,
          );
        }),
      );

    final all = await manager.resolve(request);
    expect(calls, ['error', 'torrentio', 'fallback']);
    expect(all.failures.single.addonId, 'error');
    expect(all.options.single.providerId, 'torrentio');
    expect(all.options.single.quality, '1080p');
    expect(all.options.single.height, 1080);
    expect(all.options.single.size, 123);
    final subtitle = all.options.single.subtitles.single;
    expect(subtitle.url.toString(), 'https://example.com/cc/es.vtt');
    expect(subtitle.language, 'spa');

    calls.clear();
    final preferred = await manager.resolvePreferred(request);
    expect(calls, ['error', 'torrentio']);
    expect(preferred.preferredOption?.providerId, 'torrentio');

    addons.items[0] = addons.items[0].copyWith(priority: 1);
    calls.clear();
    final first = await manager.resolve(
      request,
      mode: StreamChainMode.firstAvailable,
      addonIds: {'fallback', 'torrentio'},
    );
    expect(calls, ['fallback']);
    expect(first.options.single.providerId, 'fallback');
  });

  test(
    'Equilibra semillas y ancho de banda estimado al elegir la fuente inicial',
    () async {
      final client = MockClient(
        (_) async => http.Response('''
      {"streams":[
        {"url":"https://example.com/remux","name":"4K","size":"42 GB","seeders":4000},
        {"url":"https://example.com/ligero","name":"720p","size":"700 MB","seeders":8},
        {"url":"https://example.com/equilibrado","name":"1080p","size":"1.2 GB","seeders":53},
        {"url":"https://example.com/sin-semillas","name":"1080p","size":"800 MB","seeders":0},
        {"infoHash":"0123456789abcdef0123456789abcdef01234567","name":"720p","seeders":150}
      ]}
    ''', 200),
      );
      addTearDown(client.close);
      final manager =
          StreamManager(
              addons: _AddonSettings([
                _addon('torrentio', 1),
                _addon('backup', 2),
              ]),
            )
            ..register(
              'torrentio',
              TorrentioAdapter(
                JsonApi(HttpTransport(client)),
                resolveImdbId: (_) async => 'tt123',
              ),
            )
            ..register(
              'backup',
              _Provider(
                (_) => fail('La primera prioridad tiene fuentes viables'),
              ),
            );

      final result = await manager.resolvePreferred(request);
      expect(result.preferredOption?.url.path, '/equilibrado');
      expect(result.startupOptions.map((item) => item.url.path), [
        '/equilibrado',
        '/ligero',
        '/remux',
        '/sin-semillas',
      ]);
      expect(result.options.first.url.path, '/remux');
      expect(result.options.last.url.scheme, 'magnet');
    },
  );

  test(
    'Consulta el siguiente complemento cuando solo encuentra HTTP con cero semillas',
    () async {
      final zero = StreamOption(
        quality: '1080p',
        url: Uri.https('example.com', '/zero'),
        providerId: 'first',
        seeders: 0,
      );
      final backup = StreamOption(
        quality: '720p',
        url: Uri.https('example.com', '/backup'),
        providerId: 'backup',
      );
      final addons = _AddonSettings([_addon('first', 1), _addon('backup', 2)]);
      final manager = StreamManager(addons: addons)
        ..register('first', _Provider((_) => zero))
        ..register('backup', _Provider((_) => backup));
      final result = await manager.resolvePreferred(request);
      expect(result.startupOptions, [backup, zero]);
      expect(result.playableOptions, [zero, backup]);
      addons.items.removeLast();
      expect((await manager.resolvePreferred(request)).preferredOption, zero);
    },
  );

  test(
    'Lee subtítulos externos UTF-8 y rechaza archivos demasiado grandes',
    () async {
      final url = Uri.parse('https://example.com/captions.vtt');
      final track = SubtitleTrack(url: url, language: 'es');
      var body = '\uFEFFWEBVTT\n\nSubtítulo de prueba';
      final client = MockClient((request) async {
        expect(request.url, url);
        return http.Response(
          body,
          200,
          headers: {'content-type': 'text/vtt; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final repository = HttpSubtitleRepository(HttpTransport(client));
      expect(await repository.read(track), 'WEBVTT\n\nSubtítulo de prueba');
      body = 'a' * (2 * 1024 * 1024 + 1);
      await expectLater(repository.read(track), throwsFormatException);
    },
  );
  test(
    'Conserva el manifiesto e interpreta la resolución estructurada',
    () async {
      final client = MockClient(
        (request) async => http.Response('''
      {"streams":[
        {"url":"https://example.com/asset.mp4","name":"4K","height":480,"bitrate":950000,"variantGroup":"corte"},
        {"url":"https://example.com/manifest","mimeType":"application/dash+xml","behaviorHints":{"notWebReady":true}},
        {"url":"https://example.com/incompatible.mp4","behaviorHints":{"notWebReady":true}}
      ]}
    ''', 200),
      );
      addTearDown(client.close);
      final provider = TorrentioAdapter(
        JsonApi(HttpTransport(client)),
        resolveImdbId: (_) async => 'tt123',
      );
      final streams = await provider.getStreams(
        request,
        _addon('torrentio', 1),
      );
      expect(streams, hasLength(2));
      expect(streams.first.qualityLabel, '480p');
      expect(streams.first.bitrate, 950000);
      expect(streams.first.variantGroup, 'corte');
      expect(streams.last.delivery, StreamDelivery.dash);
      expect(streams.last.qualityLabel, 'Adaptativa');
    },
  );
}

AddonEntity _addon(String id, int priority, {bool enabled = true}) =>
    AddonEntity(
      id: id,
      name: id,
      baseUrl: Uri.parse('https://example.com/config/manifest.json'),
      isEnabled: enabled,
      priority: priority,
    );

final class _Provider implements StreamProviderContract {
  const _Provider(this._getOption);

  final StreamOption Function(AddonEntity) _getOption;

  @override
  Future<List<StreamOption>> getStreams(
    StreamRequest request,
    AddonEntity addon,
  ) async => [_getOption(addon)];
}

final class _AddonSettings implements AddonRepository {
  _AddonSettings(this.items);

  final List<AddonEntity> items;

  @override
  Future<List<AddonEntity>> list() async => items;

  @override
  Future<void> move(String id, AddonMove direction) =>
      throw UnimplementedError();

  @override
  Future<void> setEnabled(String id, bool enabled) =>
      throw UnimplementedError();
}
