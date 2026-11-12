import '../entities/media_item.dart';

enum MediaCollection { popularMovies, trending }

abstract interface class MediaRepository {
  Future<List<MediaItem>> browse(MediaCollection collection);

  Future<MediaItem> details(MediaItem media);

  Future<List<MediaItem>> search({
    required String query,
    required MediaKind kind,
    int page = 1,
  });
}
