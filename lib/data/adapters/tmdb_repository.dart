import '../../core/network/http_status_exception.dart';
import '../../domain/contracts/media_repository.dart';
import '../../domain/entities/media_item.dart';
import '../network/json_api.dart';

final class TmdbRepository implements MediaRepository {
  const TmdbRepository(this._api, {required String accessToken})
    : _accessToken = accessToken;

  final JsonApi _api;
  final String _accessToken;
  static const _genreLabels = {
    12: 'Aventura',
    14: 'Fantasía',
    16: 'Animación',
    18: 'Drama',
    27: 'Terror',
    28: 'Acción',
    35: 'Comedia',
    36: 'Historia',
    37: 'Western',
    53: 'Suspenso',
    80: 'Crimen',
    99: 'Documental',
    878: 'Ciencia ficción',
    9648: 'Misterio',
    10402: 'Música',
    10749: 'Romance',
    10751: 'Familia',
    10752: 'Bélica',
    10759: 'Acción y aventura',
    10762: 'Infantil',
    10763: 'Noticias',
    10764: 'Reality',
    10765: 'Ciencia ficción y fantasía',
    10766: 'Telenovela',
    10767: 'Entrevistas',
    10768: 'Guerra y política',
  };

  @override
  Future<List<MediaItem>> browse(MediaCollection collection) async {
    const query = {'language': 'es-PE'};
    return switch (collection) {
      MediaCollection.popularMovies => _parseItems(
        await _get('/3/movie/popular', query),
        kind: MediaKind.movie,
      ),
      MediaCollection.trending => _parseItems(
        await _get('/3/trending/all/week', query),
      ),
    };
  }

  @override
  Future<MediaItem> details(MediaItem media) async {
    final id = int.tryParse(media.id);
    if (id == null || id < 1) return media;
    final kind = media.kind;
    final payload = await _get('/3/${_resource(kind)}/$id', {
      'language': 'es-PE',
      'append_to_response': kind == MediaKind.movie
          ? 'credits,release_dates'
          : 'credits,content_ratings',
    });
    final posterPath = _text(payload['poster_path']) ?? media.posterPath;
    final rating = _rating(payload);
    final rawGenres = payload['genres'];
    final genres = rawGenres is List
        ? rawGenres
              .whereType<Map<String, dynamic>>()
              .map((genre) => _text(genre['name']))
              .whereType<String>()
        : const <String>[];
    return MediaItem(
      id: media.id,
      imdbId: _text(payload['imdb_id']) ?? media.imdbId,
      kind: kind,
      title:
          _text(payload[kind == MediaKind.movie ? 'title' : 'name']) ??
          media.title,
      overview: _text(payload['overview']) ?? media.overview,
      posterPath: posterPath,
      posterImage: _imageUri(posterPath, 'w780') ?? media.posterImage,
      backdropImage:
          _imageUri(payload['backdrop_path'], 'w1280') ?? media.backdropImage,
      releaseYear: _releaseYear(payload, kind) ?? media.releaseYear,
      genres: genres.isEmpty ? media.genres : List.unmodifiable(genres),
      type: _animatedType(payload, genres) ?? media.type,
      rating: rating ?? media.rating,
      ratingSource: rating == null ? media.ratingSource : 'TMDb',
      isPremiere: _releaseDate(payload, kind) == null
          ? media.isPremiere
          : _isPremiere(payload, kind),
      qualityLabel: media.qualityLabel,
      imdbRating: media.imdbRating,
      runtimeMinutes: _runtime(payload, kind) ?? media.runtimeMinutes,
      ageRating: _certification(payload, kind) ?? media.ageRating,
      directors: _creditNames(payload, const {'Director'}, media.directors),
      writers: _creditNames(payload, const {
        'Writer',
        'Screenplay',
        'Teleplay',
      }, media.writers),
    );
  }

  int? _runtime(Map<String, dynamic> payload, MediaKind kind) {
    final values = payload['episode_run_time'];
    final value = kind == MediaKind.movie
        ? payload['runtime']
        : (values is List
              ? values.whereType<int>().where((value) => value > 0).firstOrNull
              : null);
    return value is int && value > 0 ? value : null;
  }

  String? _certification(Map<String, dynamic> payload, MediaKind kind) {
    final movie = kind == MediaKind.movie;
    final group = payload[movie ? 'release_dates' : 'content_ratings'];
    final results = group is Map ? group['results'] : null;
    if (results is! List) return null;
    for (final country in const ['PE', 'US']) {
      for (final row in results.whereType<Map>()) {
        if (row['iso_3166_1'] != country) continue;
        final dates = row['release_dates'];
        final value = movie
            ? (dates is List
                  ? dates
                        .whereType<Map>()
                        .map((date) => _text(date['certification']))
                        .nonNulls
                        .firstOrNull
                  : null)
            : _text(row['rating']);
        if (value != null) return value;
      }
    }
    return null;
  }

  List<String> _creditNames(
    Map<String, dynamic> payload,
    Set<String> jobs,
    List<String> fallback,
  ) {
    final credits = payload['credits'];
    final crew = credits is Map ? credits['crew'] : null;
    if (crew is! List) return fallback;
    final names = {
      for (final person in crew.whereType<Map>())
        if (jobs.contains(person['job']))
          if (_text(person['name']) case final String name) name,
    };
    return names.isEmpty ? fallback : List.unmodifiable(names);
  }

  @override
  Future<List<MediaItem>> search({
    required String query,
    required MediaKind kind,
    int page = 1,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final term = query.trim();
    if (term.isEmpty) return const [];

    final payload = await _get('/3/search/${_resource(kind)}', {
      'query': term,
      'page': '$page',
      'language': 'es-PE',
    });
    return _parseItems(payload, kind: kind);
  }

  List<MediaItem> _parseItems(Map<String, dynamic> payload, {MediaKind? kind}) {
    final results = payload['results'];
    if (results is! List) {
      throw const FormatException('TMDb no devolvió la lista de resultados.');
    }
    final items = <MediaItem>[];
    for (final row in results.whereType<Map<String, dynamic>>()) {
      final itemKind =
          kind ??
          switch (row['media_type']) {
            'movie' => MediaKind.movie,
            'tv' => MediaKind.series,
            _ => null,
          };
      if (itemKind == null) continue;
      final id = row['id'];
      final title = row[itemKind == MediaKind.movie ? 'title' : 'name'];
      if (id is! int || title is! String || title.trim().isEmpty) continue;

      final poster = row['poster_path'];
      final overview = row['overview'];
      final rating = _rating(row);
      final rawGenres = row['genre_ids'];
      final genres = [
        if (rawGenres is List)
          for (final id in rawGenres)
            if (_genreLabels[id] case final String genre) genre,
      ];
      items.add(
        MediaItem(
          id: '$id',
          kind: itemKind,
          title: title,
          posterPath: poster is String ? poster : null,
          overview: overview is String ? overview : '',
          posterImage: _imageUri(poster, 'w342'),
          backdropImage: _imageUri(row['backdrop_path'], 'w1280'),
          releaseYear: _releaseYear(row, itemKind),
          genres: List.unmodifiable(genres),
          type: _animatedType(row, genres),
          rating: rating,
          ratingSource: rating == null ? null : 'TMDb',
          isPremiere: _isPremiere(row, itemKind),
        ),
      );
    }
    return items;
  }

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  DateTime? _releaseDate(Map<String, dynamic> payload, MediaKind kind) {
    final date =
        payload[kind == MediaKind.movie ? 'release_date' : 'first_air_date'];
    return date is String ? DateTime.tryParse(date) : null;
  }

  int? _releaseYear(Map<String, dynamic> payload, MediaKind kind) =>
      _releaseDate(payload, kind)?.year;

  bool _isPremiere(Map<String, dynamic> payload, MediaKind kind) {
    final date = _releaseDate(payload, kind);
    if (date == null) return false;
    final age = DateTime.now().difference(date);
    return !age.isNegative && age < const Duration(days: 90);
  }

  double? _rating(Map<String, dynamic> payload) {
    final value = payload['vote_average'];
    return value is num && value > 0 && value <= 10 ? value.toDouble() : null;
  }

  MediaType? _animatedType(
    Map<String, dynamic> payload,
    Iterable<String> genres,
  ) {
    if (!genres.any((genre) => genre.toLowerCase().startsWith('animaci'))) {
      return null;
    }
    return payload['original_language'] == 'ja'
        ? MediaType.anime
        : MediaType.cartoon;
  }

  Uri? _imageUri(Object? path, String size) {
    if (path is! String || !path.startsWith('/') || path.length < 2) {
      return null;
    }
    return Uri.https('image.tmdb.org', '/t/p/$size$path');
  }

  Future<String?> findImdbId(MediaItem media) async {
    final tmdbId = int.tryParse(media.id);
    if (tmdbId == null || tmdbId < 1) return null;

    try {
      final payload = await _get(
        '/3/${_resource(media.kind)}/$tmdbId/external_ids',
      );
      final imdbId = payload['imdb_id'];
      return imdbId is String && imdbId.isNotEmpty ? imdbId : null;
    } on HttpStatusException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) {
    if (_accessToken.isEmpty) {
      throw const FormatException('Falta configurar TMDB_READ_ACCESS_TOKEN.');
    }
    return _api.get(
      Uri.https('api.themoviedb.org', path, query),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
  }

  String _resource(MediaKind kind) => kind == MediaKind.movie ? 'movie' : 'tv';
}
