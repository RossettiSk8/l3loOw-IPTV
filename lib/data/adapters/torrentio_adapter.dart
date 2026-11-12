import '../../domain/contracts/stream_provider_contract.dart';
import '../../domain/entities/addon_entity.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/entities/stream_request.dart';
import '../../domain/entities/subtitle_track.dart';
import '../../domain/entities/video_resolution.dart';
import '../network/json_api.dart';

final class TorrentioAdapter implements StreamProviderContract {
  const TorrentioAdapter(
    this._api, {
    required Future<String?> Function(MediaItem) resolveImdbId,
  }) : _resolveImdbId = resolveImdbId;

  final JsonApi _api;
  final Future<String?> Function(MediaItem) _resolveImdbId;
  static final _torrentHash = RegExp(
    r'^(?:[a-f0-9]{40}|[a-z2-7]{32})$',
    caseSensitive: false,
  );
  static final _sourceMarker = RegExp(r'⚙\uFE0F?\s*([^\r\n]+)');
  static final _sizeMarker = RegExp(r'💾\s*([^\r\n]+)');
  static final _seedMarker = RegExp(
    r'(?:👤\uFE0F?|\bseeders?\s*[:=])[^\S\r\n]*(\d+)\b',
    caseSensitive: false,
  );
  static final _sizeLabel = RegExp(
    r'^(\d+(?:[.,]\d+)?)\s*(B|[KMGT]i?B)\b',
    caseSensitive: false,
  );

  @override
  Future<List<StreamOption>> getStreams(
    StreamRequest request,
    AddonEntity addon,
  ) async {
    final media = request.media;
    final catalogId = media.imdbId;
    final imdbId = switch (catalogId) {
      final String id when _isImdbId(id) => id,
      _ when _isImdbId(media.id) => media.id,
      _ => await _resolveImdbId(media),
    };
    if (imdbId == null || !_isImdbId(imdbId)) return const [];

    final isMovie = media.kind == MediaKind.movie;
    final type = isMovie ? 'movie' : 'series';
    final id = isMovie
        ? imdbId
        : '$imdbId:${request.season}:${request.episode}';
    final endpoint = _streamEndpoint(addon.baseUrl, type, id);
    final payload = await _api.get(endpoint);
    final streams = payload['streams'];
    if (streams is! List) {
      throw const FormatException('El complemento no devolvió streams.');
    }
    return [
      for (final item in streams.whereType<Map<String, dynamic>>())
        if (_parseStream(item, addon.id, endpoint)
            case final StreamOption stream)
          stream,
    ];
  }

  Uri _streamEndpoint(Uri configuredUrl, String type, String id) {
    final base = configuredUrl.scheme == 'stremio'
        ? configuredUrl.replace(scheme: 'https')
        : configuredUrl;
    if (!_isHttpUrl(base)) {
      throw const FormatException(
        'La URL del complemento debe usar HTTP(S) o stremio://.',
      );
    }
    final segments = base.pathSegments.toList();
    if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
    if (segments.isNotEmpty && segments.last == 'manifest.json') {
      segments.removeLast();
    }
    return base.removeFragment().replace(
      pathSegments: [...segments, 'stream', type, '$id.json'],
    );
  }

  bool _isHttpUrl(Uri url) =>
      (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;

  bool _isImdbId(String id) => RegExp(r'^tt[0-9]+$').hasMatch(id);

  StreamOption? _parseStream(
    Map<String, dynamic> item,
    String addonId,
    Uri endpoint,
  ) {
    final rawUrl = item['url'];
    final parsedUrl = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final direct = parsedUrl != null && _isHttpUrl(parsedUrl)
        ? parsedUrl
        : null;
    final hasDirect = direct != null;
    final rawHash = item['infoHash'];
    final hash = rawHash is String && _torrentHash.hasMatch(rawHash)
        ? rawHash.toLowerCase()
        : null;
    if (!hasDirect && hash == null) return null;

    final rawHints = item['behaviorHints'];
    final hints = rawHints is Map<String, dynamic> ? rawHints : null;
    if (hasDirect && hints?['proxyHeaders'] != null) return null;
    final url =
        direct ??
        Uri(scheme: 'magnet', queryParameters: {'xt': 'urn:btih:$hash'});
    final delivery = hasDirect
        ? _deliveryHint(
            item['mimeType'] ?? hints?['mimeType'] ?? item['format'],
          )
        : StreamDelivery.progressive;
    final metadata = [
      item['description'],
      item['title'],
    ].whereType<String>().join('\n');
    final height =
        parseVideoHeight(item['height'], allowBareHeight: true) ??
        parseVideoHeight(hints?['videoHeight'], allowBareHeight: true) ??
        parseVideoHeight(
          item['resolution'] ?? hints?['resolution'],
          allowBareHeight: true,
        ) ??
        parseVideoHeight(item['quality'], allowBareHeight: true) ??
        parseVideoHeight(hints?['filename']) ??
        parseVideoHeight(item['name']) ??
        parseVideoHeight(item['description']) ??
        parseVideoHeight(item['title']) ??
        parseVideoHeight(url.pathSegments.lastOrNull);
    final size =
        _parseSize(hints?['videoSize']) ??
        _parseSize(item['size']) ??
        _parseSize(_sizeMarker.firstMatch(metadata)?.group(1));
    final sourceName =
        _nonEmpty(item['source']) ??
        _nonEmpty(item['provider']) ??
        _nonEmpty(_sourceMarker.firstMatch(metadata)?.group(1));
    final seeders =
        _parseSeeders(item['seeders']) ??
        _parseSeeders(hints?['seeders']) ??
        _parseSeeders(_seedMarker.firstMatch(metadata)?.group(1));
    final fileIndex = item['fileIdx'];
    final bitrate = item['bitrate'] ?? hints?['videoBitrate'];
    final group = item['variantGroup'] ?? hints?['variantGroup'];
    final stream = StreamOption(
      quality: height == null
          ? 'Sin resolución indicada'
          : formatVideoHeight(height),
      videoHeight: height,
      url: url,
      providerId: addonId,
      size: size,
      seeders: seeders,
      sourceName: sourceName,
      torrentFileIndex: !hasDirect && fileIndex is int && fileIndex >= 0
          ? fileIndex
          : null,
      bitrate: bitrate is int && bitrate > 0 ? bitrate : null,
      variantGroup: group is String && group.trim().isNotEmpty
          ? group.trim()
          : null,
      deliveryHint: delivery,
      subtitles: _parseSubtitles(item['subtitles'], endpoint),
    );
    return hasDirect && hints?['notWebReady'] == true && !stream.isAdaptive
        ? null
        : stream;
  }

  String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  int? _parseSeeders(Object? value) {
    final count = switch (value) {
      final int count => count,
      final String count => int.tryParse(count.trim()),
      _ => null,
    };
    return count != null && count >= 0 ? count : null;
  }

  int? _parseSize(Object? value) {
    if (value is int && value > 0) return value;
    if (value is! String) return null;
    final match = _sizeLabel.firstMatch(value.trim());
    if (match == null) return null;
    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (amount == null || !amount.isFinite || amount <= 0) return null;
    final multiplier = switch (match.group(2)!.toUpperCase()) {
      'KB' => 1000,
      'MB' => 1000000,
      'GB' => 1000000000,
      'TB' => 1000000000000,
      'KIB' => 1 << 10,
      'MIB' => 1 << 20,
      'GIB' => 1 << 30,
      'TIB' => 1 << 40,
      _ => 1,
    };
    final bytes = amount * multiplier;
    return bytes.isFinite && bytes >= 1 && bytes <= 9007199254740991
        ? bytes.round()
        : null;
  }

  StreamDelivery? _deliveryHint(Object? value) => switch (value) {
    final String format => switch (format
        .toLowerCase()
        .split(';')
        .first
        .trim()) {
      'hls' ||
      'm3u8' ||
      'application/vnd.apple.mpegurl' ||
      'application/x-mpegurl' => StreamDelivery.hls,
      'dash' || 'mpd' || 'application/dash+xml' => StreamDelivery.dash,
      _ => null,
    },
    _ => null,
  };

  List<SubtitleTrack> _parseSubtitles(Object? payload, Uri endpoint) {
    if (payload is! List) return const [];
    final tracks = <Uri, SubtitleTrack>{};
    for (final row in payload.whereType<Map<String, dynamic>>()) {
      final rawUrl = row['url'];
      if (rawUrl is! String || rawUrl.trim().isEmpty) continue;
      final parsed = Uri.tryParse(rawUrl);
      if (parsed == null) continue;
      final url = endpoint.resolveUri(parsed).removeFragment();
      if (!const {'http', 'https'}.contains(url.scheme) || url.host.isEmpty) {
        continue;
      }
      final language = row['lang'];
      final label = row['label'];
      tracks.putIfAbsent(
        url,
        () => SubtitleTrack(
          url: url,
          language: language is String && language.trim().isNotEmpty
              ? language.trim()
              : 'und',
          label: label is String && label.trim().isNotEmpty
              ? label.trim()
              : null,
        ),
      );
    }
    return List.unmodifiable(tracks.values);
  }
}
