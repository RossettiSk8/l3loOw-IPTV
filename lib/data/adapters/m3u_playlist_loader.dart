import 'dart:convert';

import '../../core/network/http_transport.dart';
import '../../domain/entities/iptv_channel.dart';

final class M3uPlaylistLoader {
  const M3uPlaylistLoader(this._transport);

  final HttpTransport _transport;
  static final _title = RegExp(r'^(?:[^",]|"[^"]*")*,(.*)$');
  static final _group = RegExp(
    r'\bgroup-title="([^"]+)"',
    caseSensitive: false,
  );

  Future<List<IptvChannel>> load(Uri playlist) async {
    final bytes = await _transport.get(playlist, maxBytes: 4 * 1024 * 1024);
    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      return _parse(latin1.decode(bytes), playlist);
    }
    return _parse(content, playlist);
  }

  List<IptvChannel> _parse(String content, Uri playlist) {
    final lines = const LineSplitter().convert(content);
    final channels = <Uri, IptvChannel>{};
    var extended = false;
    String? title;
    String? group;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) {
        extended = true;
      } else if (extended && line.startsWith('#EXT-X-')) {
        // Un manifiesto HLS es una fuente; sus segmentos no son canales.
        return [IptvChannel(name: playlist.host, url: playlist, isHls: true)];
      } else if (line.startsWith('#EXTINF:')) {
        final info = line.substring('#EXTINF:'.length);
        title = _title.firstMatch(info)?.group(1)?.trim();
        group = _group.firstMatch(info)?.group(1)?.trim();
      } else if (line.startsWith('#EXTGRP:')) {
        group = line.substring('#EXTGRP:'.length).trim();
      } else if (!line.startsWith('#')) {
        final uri = Uri.tryParse(line);
        final url = uri == null || (!extended && !uri.hasScheme)
            ? null
            : parseAddress(playlist.resolveUri(uri).toString());
        if (url != null) {
          final name = title;
          channels.putIfAbsent(
            url,
            () => IptvChannel(
              name: name == null || name.isEmpty ? url.host : name,
              url: url,
              group: group,
              isHls: url.path.toLowerCase().endsWith('.m3u8'),
            ),
          );
        }
        title = null;
        group = null;
      }
    }
    if (channels.isEmpty) {
      throw const FormatException('La lista no contiene canales HTTP(S).');
    }
    return channels.values.toList(growable: false);
  }

  static Uri? parseAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.removeFragment();
  }

  Future<bool> isGone(Uri url) async {
    try {
      final status = await _transport.headStatus(url);
      return status == 404 || status == 410;
    } on Exception {
      // Una comprobación inconclusa no confirma que el enlace esté roto.
      return false;
    }
  }
}
