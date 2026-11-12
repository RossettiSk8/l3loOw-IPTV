import 'package:app_streaming/core/dependencies/memory_cache_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Aplica los límites globales de entradas y bytes retenidos', () {
    final cache = ImageCache();
    MemoryCacheService(cache: cache).configure();
    expect(cache.maximumSize, 160);
    expect(cache.maximumSizeBytes, 48 * 1024 * 1024);
  });
}
