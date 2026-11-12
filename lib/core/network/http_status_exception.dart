final class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Error HTTP $statusCode';
}
