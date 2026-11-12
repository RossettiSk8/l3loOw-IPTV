import '../contracts/media_repository.dart';
import '../entities/media_item.dart';

enum CatalogFilter {
  all,
  premieres,
  series,
  movies,
  action,
  drama,
  scienceFiction,
  comedy,
  anime,
  cartoons,
}

typedef CatalogRail = ({CatalogFilter category, List<MediaItem> items});
typedef CatalogView = ({
  MediaItem? featured,
  List<CatalogRail> rails,
  List<MediaItem>? results,
});

final class BrowseCatalog {
  const BrowseCatalog(this._repository);

  final MediaRepository _repository;

  Future<List<MediaItem>> load() async {
    // Una colección puede seguir disponible si falla la otra.
    final collections = await Future.wait(
      MediaCollection.values.map(_loadCollection),
    );
    final items = <(MediaKind, String), MediaItem>{};
    for (final collection in collections.nonNulls) {
      for (final item in collection) {
        items.putIfAbsent((item.kind, item.id), () => item);
      }
    }
    if (items.isEmpty && collections.any((result) => result == null)) {
      throw StateError('No se pudo cargar el catálogo.');
    }
    return List.unmodifiable(items.values);
  }

  Future<List<MediaItem>?> _loadCollection(MediaCollection collection) async {
    try {
      return await _repository.browse(collection);
    } on Exception {
      return null;
    }
  }

  List<MediaItem> highlights(List<MediaItem> catalog) {
    final illustrated = catalog.where((item) => item.backdropImage != null);
    return List.unmodifiable(
      (illustrated.isEmpty ? catalog : illustrated).take(5),
    );
  }

  List<CatalogRail> trendingRails(List<MediaItem> catalog) => [
    for (final category in [CatalogFilter.movies, CatalogFilter.series])
      (
        category: category,
        items: catalog.where((item) => _matches(item, category)).toList(),
      ),
  ];

  CatalogView view(
    List<MediaItem> catalog, {
    required CatalogFilter section,
    required CatalogFilter genre,
    required String query,
  }) {
    final terms = _fold(query).split(' ').where((term) => term.isNotEmpty);
    final items = [
      for (final item in catalog)
        if (_matches(item, section) &&
            _matches(item, genre) &&
            (terms.isEmpty || _matchesQuery(item, terms)))
          item,
    ];
    if (section != CatalogFilter.all ||
        genre != CatalogFilter.all ||
        terms.isNotEmpty) {
      return (featured: null, rails: const [], results: items);
    }
    final movies = items.where((item) => item.kind == MediaKind.movie);
    final featured =
        movies.where((item) => item.backdropImage != null).firstOrNull ??
        movies.firstOrNull;
    final rails = <CatalogRail>[];
    for (final category in const [
      CatalogFilter.premieres,
      CatalogFilter.series,
      CatalogFilter.movies,
      CatalogFilter.drama,
      CatalogFilter.anime,
      CatalogFilter.cartoons,
    ]) {
      final matches = items.where((item) => _matches(item, category)).toList();
      if (matches.isNotEmpty) rails.add((category: category, items: matches));
    }
    return (featured: featured, rails: rails, results: null);
  }

  bool _matches(MediaItem item, CatalogFilter filter) => switch (filter) {
    CatalogFilter.all => true,
    CatalogFilter.premieres => item.isPremiere,
    CatalogFilter.series => item.kind == MediaKind.series,
    CatalogFilter.movies => item.kind == MediaKind.movie,
    CatalogFilter.anime => item.type == MediaType.anime,
    CatalogFilter.cartoons => item.type == MediaType.cartoon,
    CatalogFilter.action => _hasGenre(item, 'accion'),
    CatalogFilter.drama => _hasGenre(item, 'drama'),
    CatalogFilter.scienceFiction => _hasGenre(item, 'ciencia ficcion'),
    CatalogFilter.comedy => _hasGenre(item, 'comedia'),
  };

  bool _hasGenre(MediaItem item, String genre) =>
      item.genres.any((label) => _fold(label).contains(genre));

  bool _matchesQuery(MediaItem item, Iterable<String> terms) {
    final format = item.kind == MediaKind.movie ? 'peliculas movies' : 'series';
    final category = switch (item.type) {
      MediaType.movie || MediaType.series => '',
      MediaType.anime => 'anime',
      MediaType.cartoon => 'dibujos animados cartoon',
    };
    final searchable = _fold(
      [
        item.title,
        ...item.genres,
        format,
        category,
        if (item.isPremiere) 'estreno estrenos',
      ].join(' '),
    );
    return terms.every(searchable.contains);
  }

  String _fold(String text) => text
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
