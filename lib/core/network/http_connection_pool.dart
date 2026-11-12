import 'package:http/http.dart' as http;

/// Reutiliza conexiones en primer plano y las cierra cuando quedan ociosas.
final class HttpConnectionPool {
  HttpConnectionPool(this._create);

  final http.Client Function() _create;
  http.Client? _client;
  int _pending = 0;
  bool _trimWhenIdle = false;
  bool _closed = false;

  Future<T> run<T>(Future<T> Function(http.Client) request) async {
    if (_closed) throw StateError('El cliente HTTP está cerrado.');
    final client = _client ??= _create();
    _pending++;
    try {
      return await request(client);
    } finally {
      _pending--;
      _trim();
    }
  }

  void suspend() {
    _trimWhenIdle = true;
    _trim();
  }

  void resume() => _trimWhenIdle = false;

  void _trim() {
    if (_trimWhenIdle && _pending == 0) _closeClient();
  }

  void _closeClient() {
    _client?.close();
    _client = null;
  }

  void close() {
    _closed = true;
    _closeClient();
  }
}
