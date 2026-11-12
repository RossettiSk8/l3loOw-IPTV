import 'dart:async';

import 'package:app_streaming/core/dependencies/media_player_optimizer.dart';
import 'package:app_streaming/core/network/http_connection_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'Cierra el cliente cuando se vuelve ocioso y lo recrea al regresar',
    () async {
      final clients = <_Client>[];
      final pool = HttpConnectionPool(() {
        final client = _Client();
        clients.add(client);
        return client;
      });
      addTearDown(pool.close);
      final response = Completer<void>();
      final request = pool.run((_) => response.future);
      pool.suspend();
      expect(clients.single.closed, isFalse);
      response.complete();
      await request;
      expect(clients.single.closed, isTrue);

      pool.resume();
      await pool.run(
        (client) async => expect(client, isNot(same(clients.first))),
      );
      expect(clients.last.closed, isFalse);
      pool.suspend();
      expect(clients.last.closed, isTrue);
    },
  );

  test(
    'Limita las decodificaciones de imagen según la función y la densidad',
    () {
      expect(
        MediaPlayerOptimizer.imageDecodeSize(
          logicalWidth: 1920,
          logicalHeight: 1080,
          pixelRatio: 3,
          panorama: true,
        ),
        (width: 1920, height: 1080),
      );
      expect(
        MediaPlayerOptimizer.imageDecodeSize(
          logicalWidth: 150,
          logicalHeight: 225,
          pixelRatio: 2,
          panorama: false,
        ),
        (width: 320, height: 480),
      );
    },
  );
}

final class _Client extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
