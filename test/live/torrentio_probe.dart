import 'dart:io';

import 'package:app_streaming/core/network/http_transport.dart';
import 'package:app_streaming/data/adapters/demo_media_repository.dart';
import 'package:app_streaming/data/adapters/torrentio_adapter.dart';
import 'package:app_streaming/data/network/json_api.dart';
import 'package:app_streaming/domain/entities/addon_entity.dart';
import 'package:app_streaming/domain/contracts/media_repository.dart';
import 'package:app_streaming/domain/entities/stream_request.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = http.Client();
  try {
    final api = JsonApi(HttpTransport(client));
    final manifestUrl = Uri.https('torrentio.strem.fun', '/manifest.json');
    final manifest = await api.get(manifestUrl);
    final resources = manifest['resources'];
    if (manifest['id'] != 'com.stremio.torrentio.addon' ||
        resources is! List ||
        !resources.any(
          (resource) =>
              resource == 'stream' ||
              resource is Map && resource['name'] == 'stream',
        )) {
      throw StateError(
        'El manifiesto público no anuncia el recurso stream de Torrentio.',
      );
    }

    final adapter = TorrentioAdapter(api, resolveImdbId: (_) async => null);
    final movies = await DemoMediaRepository().browse(
      MediaCollection.popularMovies,
    );
    final request = StreamRequest.movie(
      movies.singleWhere((movie) => movie.title == 'Big Buck Bunny'),
    );
    final options = await adapter.getStreams(
      request,
      AddonEntity(
        id: 'torrentio',
        name: 'Torrentio',
        baseUrl: manifestUrl,
        isEnabled: true,
        priority: 1,
      ),
    );
    final withMetadata = options
        .where(
          (option) =>
              option.height != null &&
              option.size != null &&
              option.sourceName != null,
        )
        .length;
    if (withMetadata == 0) {
      throw StateError(
        'Torrentio no devolvió fuentes con resolución, tamaño y origen para el corto de prueba.',
      );
    }

    final playable = options.where((option) => option.isPlayable).length;
    stdout.writeln(
      'Torrentio validado. ${options.length} opciones, '
      '$withMetadata con metadatos completos y $playable enlaces directos.',
    );
  } finally {
    client.close();
  }
}
