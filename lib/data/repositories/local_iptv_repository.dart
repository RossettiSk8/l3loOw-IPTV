import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/iptv_repository.dart';
import '../../domain/entities/iptv_channel.dart';
import '../../domain/entities/iptv_playlist.dart';
import '../adapters/m3u_playlist_loader.dart';

final class LocalIptvRepository implements IptvRepository {
  LocalIptvRepository(this._preferences, this._loader);

  static const _key = 'iptv.playlists.v1';
  static const _probeBatchSize = 6;
  final SharedPreferencesAsync _preferences;
  final M3uPlaylistLoader _loader;
  Future<void> _pending = Future.value();

  @override
  Future<List<IptvPlaylist>> list() async {
    await _pending;
    return _read();
  }

  @override
  Future<void> addPlaylist(String address) {
    final url = M3uPlaylistLoader.parseAddress(address);
    if (url == null) {
      return Future.error(
        const FormatException('Introduce una URL HTTP(S) válida.'),
      );
    }
    return _mutate(() async {
      final playlists = await _read();
      if (playlists.any((playlist) => playlist.url == url)) {
        throw const FormatException('Esta lista ya está guardada.');
      }
      final channels = await _loader.load(url);
      await _save([...playlists, IptvPlaylist(url: url, channels: channels)]);
    });
  }

  @override
  Future<void> removePlaylist(Uri url) => _mutate(() async {
    final playlists = await _read();
    await _save(playlists.where((playlist) => playlist.url != url));
  });

  @override
  Future<int> purgeBrokenLinks() => _mutate(() async {
    final playlists = await _read();
    final urls = {
      for (final playlist in playlists)
        for (final channel in playlist.channels) channel.url,
    }.toList(growable: false);
    final gone = <Uri>{};
    for (var start = 0; start < urls.length; start += _probeBatchSize) {
      await Future.wait(
        urls.skip(start).take(_probeBatchSize).map((url) async {
          if (await _loader.isGone(url)) gone.add(url);
        }),
      );
    }
    if (gone.isEmpty) return 0;

    var removed = 0;
    final filtered = <IptvPlaylist>[];
    for (final playlist in playlists) {
      final remaining = playlist.channels
          .where((channel) => !gone.contains(channel.url))
          .toList(growable: false);
      removed += playlist.channels.length - remaining.length;
      filtered.add(IptvPlaylist(url: playlist.url, channels: remaining));
    }
    await _save(filtered);
    return removed;
  });

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<IptvPlaylist>> _read() async {
    final saved = await _preferences.getString(_key);
    if (saved == null) return const [];
    final rows = jsonDecode(saved) as List<dynamic>;
    return List.unmodifiable([
      for (final row in rows.cast<Map<String, dynamic>>())
        IptvPlaylist(
          url: Uri.parse(row['url'] as String),
          channels: [
            for (final channel
                in (row['channels'] as List<dynamic>)
                    .cast<Map<String, dynamic>>())
              IptvChannel(
                name: channel['name'] as String,
                url: Uri.parse(channel['url'] as String),
                group: channel['group'] as String?,
                isHls: channel['isHls'] as bool,
              ),
          ],
        ),
    ]);
  }

  Future<void> _save(Iterable<IptvPlaylist> playlists) =>
      _preferences.setString(
        _key,
        jsonEncode([
          for (final playlist in playlists)
            {
              'url': playlist.url.toString(),
              'channels': [
                for (final channel in playlist.channels)
                  {
                    'name': channel.name,
                    'url': channel.url.toString(),
                    'group': channel.group,
                    'isHls': channel.isHls,
                  },
              ],
            },
        ]),
      );
}
