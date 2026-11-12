import 'package:app_streaming/core/network/http_transport.dart';
import 'package:app_streaming/data/adapters/tmdb_repository.dart';
import 'package:app_streaming/data/network/json_api.dart';
import 'package:app_streaming/domain/contracts/media_repository.dart';
import 'package:app_streaming/domain/entities/media_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Devuelve películas populares y tendencias sin incluir personas',
    () async {
      final client = MockClient((request) async {
        final body = switch (request.url.path) {
          '/3/movie/popular' =>
            '{"results":[{"id":1,"title":"Una película","backdrop_path":"/hero.jpg"}]}',
          '/3/trending/all/week' =>
            '''
          {"results":[
            {"id":2,"media_type":"person","name":"Intérprete"},
            {"id":3,"media_type":"tv","name":"Una serie","poster_path":"/poster.jpg",
             "genre_ids":[16,10765],"original_language":"ja","first_air_date":"2021-04-01",
             "vote_average":8.4}
          ]}
        ''',
          _ => fail('Ruta de TMDb inesperada: ${request.url.path}'),
        };
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final repository = TmdbRepository(
        JsonApi(HttpTransport(client)),
        accessToken: 'fixture',
      );

      final movies = await repository.browse(MediaCollection.popularMovies);
      expect(movies.single.kind, MediaKind.movie);
      expect(
        movies.single.backdropImage.toString(),
        'https://image.tmdb.org/t/p/w1280/hero.jpg',
      );
      final trending = await repository.browse(MediaCollection.trending);
      expect(trending.single.kind, MediaKind.series);
      expect(trending.single.type, MediaType.anime);
      expect(trending.single.genres, [
        'Animación',
        'Ciencia ficción y fantasía',
      ]);
      expect(trending.single.releaseYear, 2021);
      expect(trending.single.rating, 8.4);
      expect(
        trending.single.posterImage.toString(),
        'https://image.tmdb.org/t/p/w342/poster.jpg',
      );
    },
  );

  test('Busca series y traduce el ID de TMDb a IMDb', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.themoviedb.org');
      expect(request.headers['Authorization'], 'Bearer fixture');
      switch (request.url.path) {
        case '/3/search/tv':
          expect(request.url.queryParameters['query'], 'Serie & amigos');
          expect(request.url.queryParameters['page'], '2');
          return http.Response('''
            {"results":[
              {"id":42,"name":"Serie & amigos","poster_path":"/poster.jpg","overview":"Resumen"}
            ]}
          ''', 200);
        case '/3/tv/42/external_ids':
          return http.Response('{"imdb_id":"tt123"}', 200);
        case '/3/tv/42':
          return http.Response('''
            {"id":42,"first_air_date":"2021-04-01","genres":[{"name":"Drama"}],
             "overview":"Sinopsis completa","episode_run_time":[42],"vote_average":8.4,
             "credits":{"crew":[{"name":"Directora","job":"Director"},{"name":"Guionista","job":"Writer"}]},
             "content_ratings":{"results":[{"iso_3166_1":"US","rating":"TV-14"}]}}
            ''', 200);
        default:
          fail('Ruta de TMDb inesperada: ${request.url.path}');
      }
    });
    addTearDown(client.close);
    final repository = TmdbRepository(
      JsonApi(HttpTransport(client)),
      accessToken: 'fixture',
    );

    final items = await repository.search(
      query: '  Serie & amigos  ',
      kind: MediaKind.series,
      page: 2,
    );
    final item = items.single;
    expect(item.id, '42');
    expect(item.title, 'Serie & amigos');
    expect(item.kind, MediaKind.series);
    expect(item.posterPath, '/poster.jpg');
    expect(item.overview, 'Resumen');
    expect(await repository.findImdbId(item), 'tt123');
    final details = await repository.details(item);
    expect(details.title, item.title);
    expect(details.overview, 'Sinopsis completa');
    expect(details.year, 2021);
    expect(details.genres, ['Drama']);
    expect(details.runtimeMinutes, 42);
    expect(details.ageRating, 'TV-14');
    expect(details.directors, ['Directora']);
    expect(details.writers, ['Guionista']);
    expect(details.imdbRating, isNull);
    expect(details.rating, 8.4);
    expect(details.ratingSource, 'TMDb');
    expect(details.posterImage?.path, '/t/p/w780/poster.jpg');
  });
}
