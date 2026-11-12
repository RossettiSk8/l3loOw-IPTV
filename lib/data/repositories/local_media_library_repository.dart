import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/media_library_repository.dart';
import '../../domain/entities/media_item.dart';

final class LocalMediaLibraryRepository implements MediaLibraryRepository {
  const LocalMediaLibraryRepository(this._preferences);

  static const _key = 'media.library.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<MediaItem>> list() async {
    final raw = await _preferences.getString(_key);
    final rows = raw == null ? null : jsonDecode(raw);
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (_decode(row) case final MediaItem media) media,
    ];
  }

  MediaItem? _decode(Map<String, dynamic> row) {
    if (row case {'id': final String id, 'title': final String title}) {
      final kind = MediaKind.values
          .where((kind) => kind.name == row['kind'])
          .firstOrNull;
      if (kind == null) return null;
      return MediaItem(
        id: id,
        kind: kind,
        title: title,
        imdbId: row['imdbId'] as String?,
        posterPath: row['posterPath'] as String?,
        overview: row['overview'] as String? ?? '',
        posterImage: _uri(row['posterImage']),
        backdropImage: _uri(row['backdropImage']),
        releaseYear: row['releaseYear'] as int?,
        genres: _names(row['genres']),
        type: MediaType.values
            .where((type) => type.name == row['type'])
            .firstOrNull,
        isPremiere: row['isPremiere'] == true,
        rating: (row['rating'] as num?)?.toDouble(),
        ratingSource: row['ratingSource'] as String?,
        imdbRating: (row['imdbRating'] as num?)?.toDouble(),
        qualityLabel: row['qualityLabel'] as String?,
        runtimeMinutes: row['runtimeMinutes'] as int?,
        ageRating: row['ageRating'] as String?,
        directors: _names(row['directors']),
        writers: _names(row['writers']),
      );
    }
    return null;
  }

  Uri? _uri(Object? value) => value is String ? Uri.tryParse(value) : null;
  List<String> _names(Object? values) =>
      values is List ? List.unmodifiable(values.whereType<String>()) : const [];

  @override
  Future<void> save(List<MediaItem> items) => _preferences.setString(
    _key,
    jsonEncode([
      for (final item in items)
        {
          'id': item.id,
          'kind': item.kind.name,
          'title': item.title,
          'imdbId': item.imdbId,
          'posterPath': item.posterPath,
          'overview': item.overview,
          'posterImage': item.posterImage?.toString(),
          'backdropImage': item.backdropImage?.toString(),
          'releaseYear': item.releaseYear,
          'genres': item.genres,
          'type': item.type.name,
          'isPremiere': item.isPremiere,
          'rating': item.rating,
          'ratingSource': item.ratingSource,
          'imdbRating': item.imdbRating,
          'qualityLabel': item.qualityLabel,
          'runtimeMinutes': item.runtimeMinutes,
          'ageRating': item.ageRating,
          'directors': item.directors,
          'writers': item.writers,
        },
    ]),
  );
}
