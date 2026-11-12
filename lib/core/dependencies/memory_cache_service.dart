import 'package:flutter/painting.dart';

/// Aplica el presupuesto de imágenes retenidas por el motor de Flutter.
final class MemoryCacheService {
  MemoryCacheService({ImageCache? cache})
    : _cache = cache ?? PaintingBinding.instance.imageCache;

  static const maximumImages = 160;
  static const maximumBytes = 48 * 1024 * 1024;

  final ImageCache _cache;

  void configure() {
    _cache.maximumSize = maximumImages;
    _cache.maximumSizeBytes = maximumBytes;
  }

  void trim() => _cache.clear();
}
