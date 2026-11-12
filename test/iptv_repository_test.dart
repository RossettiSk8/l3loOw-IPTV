import 'package:app_streaming/core/network/http_transport.dart';
import 'package:app_streaming/data/adapters/m3u_playlist_loader.dart';
import 'package:app_streaming/data/repositories/local_iptv_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test(
    'Importa M3U y HLS, conserva las listas y purga solo las bajas confirmadas',
    () async {
      final original = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
      final probes = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'HEAD') {
          probes.add(request.url.path);
          return http.Response('', switch (request.url.path) {
            '/broken' => 404,
            '/gone' => 410,
            '/temporary' => 503,
            '/restricted' => 403,
            '/unsupported' => 405,
            _ => 200,
          });
        }
        expect(request.method, 'GET');
        return http.Response(switch (request.url.path) {
          '/channels.m3u' =>
            '''
            #EXTM3U
            #EXTINF:-1 group-title="Cine, Cultura",Canal local
            /live/one.m3u8
            https://example.com/live/one.m3u8
            https://example.com/broken
            https://example.com/gone
            https://example.com/temporary
            https://example.com/restricted
            https://example.com/unsupported
            file:///video.mp4
          ''',
          '/feed' =>
            '''
            #EXTM3U
            #EXT-X-TARGETDURATION:6
            #EXTINF:6,
            segment.ts
          ''',
          _ => '<html><body>Sin lista</body></html>',
        }, 200);
      });
      addTearDown(client.close);
      final loader = M3uPlaylistLoader(HttpTransport(client));
      LocalIptvRepository repository() =>
          LocalIptvRepository(SharedPreferencesAsync(), loader);
      final initial = repository();
      await expectLater(
        initial.addPlaylist('file:///test.m3u'),
        throwsFormatException,
      );
      await expectLater(
        initial.addPlaylist('https://example.com/html'),
        throwsFormatException,
      );
      await Future.wait([
        initial.addPlaylist('https://example.com/channels.m3u'),
        initial.addPlaylist('https://example.com/feed'),
      ]);
      await expectLater(
        initial.addPlaylist('https://example.com/channels.m3u#duplicado'),
        throwsFormatException,
      );

      final reopened = repository();
      final lists = await reopened.list();
      expect(lists.first.channels, hasLength(6));
      final channel = lists.first.channels.first;
      expect(channel.name, 'Canal local');
      expect(channel.group, 'Cine, Cultura');
      expect(channel.url.toString(), 'https://example.com/live/one.m3u8');
      expect(channel.isHls, isTrue);
      expect(lists.last.channels.single.url.path, '/feed');
      expect(lists.last.channels.single.isHls, isTrue);

      expect(await reopened.purgeBrokenLinks(), 2);
      expect(
        probes,
        unorderedEquals([
          '/live/one.m3u8',
          '/broken',
          '/gone',
          '/temporary',
          '/restricted',
          '/unsupported',
          '/feed',
        ]),
      );
      expect(
        (await repository().list()).first.channels.map((item) => item.url.path),
        ['/live/one.m3u8', '/temporary', '/restricted', '/unsupported'],
      );
      await reopened.removePlaylist(lists.first.url);
      expect((await repository().list()).single.url, lists.last.url);
    },
  );
}
