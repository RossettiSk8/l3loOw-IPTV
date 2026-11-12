import 'dart:convert';

import '../../core/network/http_transport.dart';
import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/subtitle_track.dart';

final class HttpSubtitleRepository implements SubtitleRepository {
  const HttpSubtitleRepository(this._transport);

  final HttpTransport _transport;

  @override
  Future<String> read(SubtitleTrack track) async {
    final url = track.url;
    if ((url.scheme != 'https' && url.scheme != 'http') || url.host.isEmpty) {
      throw const FormatException('URL de subtítulos inválida.');
    }
    final bytes = await _transport.get(url, maxBytes: 2 * 1024 * 1024);
    return utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '').trimLeft();
  }
}
