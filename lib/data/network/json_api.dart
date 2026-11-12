import 'dart:convert';

import '../../core/network/http_transport.dart';

final class JsonApi {
  const JsonApi(this._transport);

  final HttpTransport _transport;

  Future<Map<String, dynamic>> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final bytes = await _transport.get(
      uri,
      headers: {'Accept': 'application/json', ...headers},
    );
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Se esperaba un objeto JSON.');
    }
    return body;
  }
}
