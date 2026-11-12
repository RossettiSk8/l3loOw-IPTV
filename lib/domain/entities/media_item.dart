enum MediaKind { movie, series }

enum MediaType { movie, series, anime, cartoon }

final class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.posterPath,
    required this.overview,
    this.imdbId,
    this.posterImage,
    this.backdropImage,
    int? releaseYear,
    int? year,
    this.genres = const [],
    MediaType? type,
    this.isPremiere = false,
    this.rating,
    this.ratingSource,
    this.qualityLabel,
    this.runtimeMinutes,
    this.ageRating,
    this.imdbRating,
    this.directors = const [],
    this.writers = const [],
  }) : _type = type,
       releaseYear = releaseYear ?? year;

  final String id;
  final String? imdbId;
  final MediaKind kind;
  final String title;
  final String? posterPath;
  final String overview;
  final Uri? posterImage;
  final Uri? backdropImage;
  final int? releaseYear;
  final List<String> genres;
  final MediaType? _type;
  final bool isPremiere;
  final double? rating;
  final String? ratingSource;
  final String? qualityLabel;
  final int? runtimeMinutes;
  final String? ageRating;
  final double? imdbRating;
  final List<String> directors;
  final List<String> writers;

  MediaType get type =>
      _type ?? (kind == MediaKind.movie ? MediaType.movie : MediaType.series);

  int? get year => releaseYear;
}
