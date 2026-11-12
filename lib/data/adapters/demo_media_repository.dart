import '../../domain/contracts/media_repository.dart';
import '../../domain/entities/media_item.dart';

final class DemoMediaRepository implements MediaRepository {
  static final _titles = [
    _title(
      'charge',
      'Charge',
      'En un futuro con escasez de energía, un hombre se infiltra en una fábrica de baterías y se encuentra con un robot de seguridad.',
      year: 2022,
      genres: ['Ciencia ficción', 'Acción'],
      backdrop: 'charge-backdrop.png',
      imdbId: 'tt24787066',
      runtimeMinutes: 5,
      imdbRating: 7.6,
      directors: ['Hjalti Hjálmarsson'],
      writers: ['Hjalti Hjálmarsson'],
      qualityLabel: '1080p',
    ),
    _title(
      'spring',
      'Spring',
      'Una joven pastora y su perro se encuentran con espíritus antiguos que marcan el cambio de estación.',
      year: 2019,
      genres: ['Animación', 'Fantasía'],
      type: MediaType.cartoon,
    ),
    _title(
      'sprite-fright',
      'Sprite Fright',
      'Una excursión al bosque da un giro inesperado cuando un grupo de jóvenes se cruza con sus diminutos habitantes.',
      year: 2021,
      genres: ['Animación', 'Terror'],
    ),
    _title(
      'wing-it',
      'Wing It!',
      'Un ingeniero y una aspirante a piloto quedan atrapados en una nave fuera de control.',
      year: 2023,
      genres: ['Animación', 'Comedia'],
      type: MediaType.cartoon,
    ),
    _title(
      'agent-327',
      'Agent 327',
      'Una investigación lleva a un agente secreto a una barbería con más secretos de los que aparenta.',
      year: 2017,
      genres: ['Animación', 'Acción'],
    ),
    _title(
      'sintel',
      'Sintel',
      'Una viajera recorre tierras desconocidas en busca del dragón al que salvó de pequeño.',
      year: 2010,
      genres: ['Animación', 'Fantasía'],
    ),
    _title(
      'big-buck-bunny',
      'Big Buck Bunny',
      'Un conejo tranquilo decide enfrentarse a tres vecinos que han alterado la paz del bosque.',
      imdbId: 'tt1254207',
      year: 2008,
      genres: ['Animación', 'Comedia'],
      type: MediaType.cartoon,
      qualityLabel: '720p',
    ),
    _title(
      'tears-of-steel',
      'Tears of Steel',
      'En un Ámsterdam futurista, científicos y combatientes intentan detener una amenaza robótica.',
      year: 2012,
      genres: ['Ciencia ficción', 'Acción', 'Drama'],
    ),
    _title(
      'coffee-run',
      'Coffee Run',
      'Entre tazas de café, una joven revive recuerdos de una relación pasada.',
      year: 2020,
      genres: ['Animación', 'Drama'],
      type: MediaType.cartoon,
    ),
    _title(
      'hero',
      'Hero',
      'Un héroe animado emprende una aventura dibujada en un mundo tridimensional.',
      year: 2018,
      genres: ['Animación', 'Aventura'],
      type: MediaType.cartoon,
    ),
    _title(
      'glass-half',
      'Glass Half',
      'Dos visitantes de una galería tienen opiniones muy distintas sobre las obras que ven.',
      year: 2015,
      genres: ['Animación', 'Comedia'],
      type: MediaType.cartoon,
    ),
    _title(
      'elephants-dream',
      'Elephants Dream',
      'Dos personajes exploran una máquina extraña que pone a prueba su manera de ver el mundo.',
      year: 2006,
      genres: ['Animación', 'Ciencia ficción'],
    ),
    _title(
      'la-ultima-frecuencia',
      'La última frecuencia',
      'Una operadora de radio recibe desde un observatorio abandonado la señal de una expedición que desapareció hace décadas.',
      year: 2026,
      genres: ['Drama', 'Ciencia ficción'],
      kind: MediaKind.series,
      isPremiere: true,
      rating: 8.4,
      poster: 'la-ultima-frecuencia.jpg',
      backdrop: 'frecuencia-backdrop.jpg',
      runtimeMinutes: 44,
      ageRating: '13+',
    ),
    _title(
      'correo-del-cielo',
      'Correo del cielo',
      'Una mensajera recorre ciudades flotantes para entregar una carta capaz de cambiar el rumbo de las islas.',
      year: 2026,
      genres: ['Animación', 'Aventura', 'Fantasía'],
      kind: MediaKind.series,
      type: MediaType.anime,
      isPremiere: true,
      rating: 8.2,
      poster: 'correo-del-cielo.jpg',
      backdrop: 'correo-backdrop.jpg',
      runtimeMinutes: 24,
      ageRating: '7+',
    ),
    _title(
      'estacion-mareas',
      'Estación Mareas',
      'Una buza de rescate investiga las luces que vuelven a encenderse en una central mareomotriz clausurada.',
      year: 2026,
      genres: ['Drama', 'Misterio'],
      kind: MediaKind.series,
      isPremiere: true,
      rating: 7.9,
      poster: 'estacion-mareas.jpg',
    ),
    _title(
      'jardin-de-luciernagas',
      'El jardín de las luciérnagas',
      'Un aprendiz de jardinero sigue las luces de un invernadero y descubre por qué sus flores solo abren de noche.',
      year: 2026,
      genres: ['Animación', 'Fantasía', 'Aventura'],
      type: MediaType.anime,
      isPremiere: true,
      rating: 8.0,
      poster: 'jardin-de-luciernagas.jpg',
    ),
  ];

  @override
  Future<MediaItem> details(MediaItem media) async =>
      _titles.firstWhere((movie) => movie.id == media.id, orElse: () => media);

  @override
  Future<List<MediaItem>> browse(MediaCollection collection) async {
    final items = switch (collection) {
      MediaCollection.popularMovies => _titles.take(8),
      MediaCollection.trending => _titles.skip(4),
    };
    return List.unmodifiable(items);
  }

  @override
  Future<List<MediaItem>> search({
    required String query,
    required MediaKind kind,
    int page = 1,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final term = query.trim().toLowerCase();
    if (page > 1 || term.isEmpty) return const [];
    return _titles
        .where(
          (movie) =>
              movie.kind == kind && movie.title.toLowerCase().contains(term),
        )
        .toList();
  }

  static MediaItem _title(
    String id,
    String title,
    String overview, {
    required int year,
    required List<String> genres,
    String? imdbId,
    String? backdrop,
    String? poster,
    MediaKind kind = MediaKind.movie,
    MediaType? type,
    bool isPremiere = false,
    double? rating,
    String? qualityLabel,
    int? runtimeMinutes,
    String? ageRating,
    double? imdbRating,
    List<String> directors = const [],
    List<String> writers = const [],
  }) {
    return MediaItem(
      id: 'demo-$id',
      imdbId: imdbId,
      kind: kind,
      type: type,
      isPremiere: isPremiere,
      rating: rating,
      qualityLabel: qualityLabel,
      runtimeMinutes: runtimeMinutes,
      ageRating: ageRating,
      imdbRating: imdbRating,
      directors: directors,
      writers: writers,
      title: title,
      overview: overview,
      posterPath: null,
      posterImage: _asset(poster ?? '$id.webp'),
      backdropImage: backdrop == null ? null : _asset(backdrop),
      releaseYear: year,
      genres: List.unmodifiable(genres),
    );
  }

  static Uri _asset(String name) =>
      Uri(scheme: 'asset', path: 'assets/catalog/$name');
}
