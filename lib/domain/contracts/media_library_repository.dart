import '../entities/media_item.dart';

abstract interface class MediaLibraryRepository {
  Future<List<MediaItem>> list();

  Future<void> save(List<MediaItem> items);
}
