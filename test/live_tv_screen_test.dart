import 'package:app_streaming/domain/contracts/iptv_repository.dart';
import 'package:app_streaming/domain/contracts/subtitle_repository.dart';
import 'package:app_streaming/domain/entities/iptv_channel.dart';
import 'package:app_streaming/domain/entities/iptv_playlist.dart';
import 'package:app_streaming/domain/entities/subtitle_track.dart';
import 'package:app_streaming/domain/repositories/list_live_channels.dart';
import 'package:app_streaming/presentation/screens/live_tv_screen.dart';
import 'package:app_streaming/presentation/widgets/tv_action.dart';
// Usa la misma biblioteca de Material que la aplicación en el SDK de LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Construye solo los canales cercanos y abre la siguiente página',
    (tester) async {
      final channels = [
        for (var index = 1; index <= 220; index++)
          IptvChannel(
            name: 'Canal $index',
            url: Uri.https('example.com', '/$index'),
          ),
      ];
      final repository = _IptvLibrary([
        IptvPlaylist(
          url: Uri.https('example.com', '/uno.m3u'),
          channels: channels.take(100),
        ),
        IptvPlaylist(
          url: Uri.https('example.com', '/dos.m3u'),
          channels: channels.skip(99),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveTvScreen(
            listChannels: ListLiveChannels(repository),
            subtitles: const _Subtitles(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Canal 1'), findsOneWidget);
      expect(find.text('Canal 100'), findsNothing);
      expect(
        find.byType(TvAction, skipOffstage: false).evaluate().length,
        lessThan(30),
      );

      final more = find.text('Cargar más canales');
      await tester.scrollUntilVisible(more, 500);
      expect(find.text('Canal 101'), findsNothing);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Canal 101'), findsOneWidget);
      expect(find.text('Canal 1'), findsNothing);
      expect(
        find.byType(TvAction, skipOffstage: false).evaluate().length,
        lessThan(30),
      );
    },
  );
}

class _IptvLibrary implements IptvRepository {
  const _IptvLibrary(this.playlists);

  final List<IptvPlaylist> playlists;

  @override
  Future<List<IptvPlaylist>> list() async => playlists;

  @override
  Future<void> addPlaylist(String address) => throw UnimplementedError();

  @override
  Future<int> purgeBrokenLinks() => throw UnimplementedError();

  @override
  Future<void> removePlaylist(Uri url) => throw UnimplementedError();
}

class _Subtitles implements SubtitleRepository {
  const _Subtitles();

  @override
  Future<String> read(SubtitleTrack track) => throw UnimplementedError();
}
