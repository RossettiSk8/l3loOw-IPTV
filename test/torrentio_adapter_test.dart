import 'package:app_streaming/core/network/http_transport.dart';
import 'package:app_streaming/data/adapters/torrentio_adapter.dart';
import 'package:app_streaming/data/network/json_api.dart';
import 'package:app_streaming/data/repositories/local_addon_repository.dart';
import 'package:app_streaming/data/streams/stream_manager.dart';
import 'package:app_streaming/domain/contracts/addon_repository.dart';
import 'package:app_streaming/domain/contracts/stream_provider_contract.dart';
import 'package:app_streaming/domain/entities/addon_entity.dart';
import 'package:app_streaming/domain/entities/media_item.dart';
import 'package:app_streaming/domain/entities/stream_option.dart';
import 'package:app_streaming/domain/entities/stream_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _request = StreamRequest.movie(
  const MediaItem(
    id: 'tt1254207',
    kind: MediaKind.movie,
    title: 'Big Buck Bunny',
    posterPath: null,
    overview: '',
  ),
);

final _torrentio = AddonEntity(
  id: 'torrentio',
  name: 'Torrentio',
  baseUrl: Uri.parse(
    'stremio://example.com/filtro%7Ccalidad/manifest.json?lang=es#addon',
  ),
  isEnabled: false,
  priority: 2,
);

void main() {
  test(
    'Consulta un manifiesto configurado y distingue enlaces de torrents',
    () async {
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.pathSegments, [
          'filtro|calidad',
          'stream',
          'movie',
          'tt1254207.json',
        ]);
        expect(request.url.queryParameters, {'lang': 'es'});
        expect(request.url.hasFragment, isFalse);
        return http.Response(
          r'''
        {"streams":[
          {"name":"Torrentio\n4k","title":"Big Buck Bunny\n👤 1 💾 7.1 GB ⚙️ EXT",
           "infoHash":"0123456789ABCDEF0123456789ABCDEF01234567","fileIdx":0},
          {"name":"Torrentio\n480p","description":"Big Buck Bunny\n💾 531,71 MB ⚙️ Archivo abierto",
           "url":"https://example.com/video-480.mp4"},
          {"name":"Torrentio\n720p","title":"💾 1 GB ⚙️ Origen",
           "url":"https://example.com/video-720.mp4","behaviorHints":{"videoSize":123456,"seeders":"24"}},
          {"name":"Torrentio\n1080p","size":"2 GiB","source":"Catálogo",
           "url":"https://example.com/video-1080.mp4","seeders":0,"title":"👤 80"}
        ]}
        ''',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final adapter = TorrentioAdapter(
        JsonApi(HttpTransport(client)),
        resolveImdbId: (_) async => fail('La consulta ya tiene un ID IMDb'),
      );

      final options = await adapter.getStreams(_request, _torrentio);
      expect(options.map((option) => option.qualityLabel), [
        '4K',
        '480p',
        '720p',
        '1080p',
      ]);
      expect(options.map((option) => option.size), [
        7100000000,
        531710000,
        123456,
        2 << 30,
      ]);
      expect(options.map((option) => option.sourceName), [
        'EXT',
        'Archivo abierto',
        'Origen',
        'Catálogo',
      ]);
      expect(options.map((option) => option.seeders), [1, null, 24, 0]);
      expect(
        options.first.url.queryParameters['xt'],
        'urn:btih:0123456789abcdef0123456789abcdef01234567',
      );
      expect(options.first.torrentFileIndex, 0);
      expect(options.first.isPlayable, isFalse);
      expect(options.skip(1).every((option) => option.isPlayable), isTrue);
    },
  );

  test(
    'Aplica la configuración guardada en el mismo gestor y tras reabrir',
    () async {
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      final demo = AddonEntity(
        id: 'demo',
        name: 'Video de prueba',
        baseUrl: Uri.https('example.com', '/demo.mp4'),
        isEnabled: true,
        priority: 1,
      );
      final defaults = [demo, _torrentio];
      final repo = LocalAddonRepository(
        SharedPreferencesAsync(),
        defaults: defaults,
      );
      var torrentioCalls = 0;
      final client = MockClient((_) async {
        torrentioCalls++;
        return http.Response('''
        {"streams":[
          {"infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0},
          {"infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":1}
        ]}
      ''', 200);
      });
      addTearDown(client.close);
      final torrentio = TorrentioAdapter(
        JsonApi(HttpTransport(client)),
        resolveImdbId: (_) async => null,
      );
      StreamManager managerFor(AddonRepository repository) =>
          StreamManager(addons: repository)
            ..register('torrentio', torrentio)
            ..register('demo', const _DirectProvider());
      final manager = managerFor(repo);
      final initial = await manager.resolve(_request);
      expect(initial.playableOptions.single.providerId, 'demo');
      expect(torrentioCalls, 0);

      final updates = Future.wait([
        repo.setEnabled('torrentio', true),
        repo.move('torrentio', AddonMove.up),
      ]);
      final updated = await manager.resolve(
        _request,
        mode: StreamChainMode.firstAvailable,
      );
      await updates;
      expect(updated.options.map((option) => option.providerId), [
        'torrentio',
        'torrentio',
        'demo',
      ]);
      expect(updated.options.take(2).map((option) => option.torrentFileIndex), [
        0,
        1,
      ]);
      expect(updated.playableOptions.single.providerId, 'demo');

      await repo.setEnabled('demo', false);
      final reopened = LocalAddonRepository(
        SharedPreferencesAsync(),
        defaults: defaults,
      );
      final saved = await reopened.list();
      expect(
        saved.map((addon) => (addon.id, addon.priority, addon.isEnabled)),
        [('torrentio', 1, true), ('demo', 2, false)],
      );
      final result = await managerFor(reopened).resolve(_request);
      expect(result.options.map((option) => option.providerId), [
        'torrentio',
        'torrentio',
      ]);
      expect(result.playableOptions, isEmpty);
    },
  );
}

final class _DirectProvider implements StreamProviderContract {
  const _DirectProvider();

  @override
  Future<List<StreamOption>> getStreams(
    StreamRequest request,
    AddonEntity addon,
  ) async => [
    StreamOption(quality: '720p', url: addon.baseUrl, providerId: addon.id),
  ];
}
