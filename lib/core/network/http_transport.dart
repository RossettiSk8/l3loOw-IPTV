import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_connection_pool.dart';
import 'http_status_exception.dart';

final class HttpTransport {
  const HttpTransport(http.Client client) : _client = client, _pool = null;
  const HttpTransport.managed(HttpConnectionPool pool)
    : _pool = pool,
      _client = null;

  final http.Client? _client;
  final HttpConnectionPool? _pool;

  Future<T> _withClient<T>(Future<T> Function(http.Client) request) =>
      _pool?.run(request) ?? request(_client!);

  Future<int> headStatus(Uri uri) => _withClient((client) async {
    final response = await client
        .send(http.Request('HEAD', uri))
        .timeout(const Duration(seconds: 6));
    await response.stream.listen(null).cancel();
    return response.statusCode;
  });

  Future<Uint8List> get(
    Uri uri, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) => _withClient((client) async {
    if (maxBytes != null) return _getLimited(client, uri, headers, maxBytes);

    final response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpStatusException(response.statusCode);
    }
    return response.bodyBytes;
  });

  Future<Uint8List> _getLimited(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
    int maxBytes,
  ) async {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    const timeout = Duration(seconds: 6);
    final response = await client.send(request).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen(null).cancel();
      throw HttpStatusException(response.statusCode);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('La respuesta supera el tamaño permitido.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}
