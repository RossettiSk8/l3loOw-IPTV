import 'dart:async';

import 'package:app_streaming/core/dependencies/app_dependencies.dart';
import 'package:app_streaming/core/dependencies/power_management_service.dart';
import 'package:app_streaming/domain/contracts/media_repository.dart';
import 'package:app_streaming/domain/contracts/subtitle_repository.dart';
import 'package:app_streaming/domain/entities/media_item.dart';
import 'package:app_streaming/domain/entities/stream_option.dart';
import 'package:app_streaming/domain/entities/subtitle_track.dart';
import 'package:app_streaming/main.dart';
import 'package:app_streaming/presentation/screens/detail_screen.dart';
import 'package:app_streaming/presentation/screens/home_screen.dart';
import 'package:app_streaming/presentation/screens/player_screen.dart';
import 'package:app_streaming/presentation/widgets/app_settings_provider.dart';
import 'package:app_streaming/presentation/widgets/home_catalog.dart';
import 'package:app_streaming/presentation/widgets/power_management_scope.dart';
import 'package:app_streaming/presentation/widgets/tv_action.dart';
// Usa la misma biblioteca de Material que la aplicación en el SDK de LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  setUp(() {
    final original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
  });

  testWidgets('El mando desplaza el carrusel hasta un póster fuera de vista', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AppStreaming());
    await tester.pumpAndSettle();
    expect(find.text('Trending Movies'), findsOneWidget);
    expect(find.text('Trending Series'), findsNothing);
    expect(find.text('TV en Vivo'), findsNothing);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedActionLabels(tester), ['Ver detalles de Charge']);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedActionLabels(tester), [
      'Ver detalles de La última frecuencia',
    ]);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusedActionLabels(tester), ['Ver detalles de Charge']);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.textContaining('una fábrica de baterías'), findsOneWidget);
    expect(find.text('2022'), findsOneWidget);
    expect(find.text('Ciencia ficción · Acción'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('IMDb 7.6'), findsOneWidget);
    expect(
      find.textContaining('Hjalti Hjálmarsson', findRichText: true),
      findsNWidgets(2),
    );
    expect(find.text('Reparto'), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedActionLabels(tester), ['Charge']);
    for (var step = 0; step < 5; step++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focusedActionLabels(tester), ['Sintel']);
    final poster = find.byWidgetPredicate(
      (widget) => widget is CatalogPoster && widget.media.title == 'Sintel',
    );
    final bounds = tester.getRect(poster);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(390));
    await _press(tester, LogicalKeyboardKey.select);
    expect(
      tester.widget<DetailScreen>(find.byType(DetailScreen)).media.title,
      'Sintel',
    );
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Trending Series'),
      220,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Trending Series'), findsOneWidget);
  });

  testWidgets(
    'Desliza el destacado y conserva un título guardado en Biblioteca',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Finder action(String label) => find.byWidgetPredicate(
        (widget) => widget is TvAction && widget.label == label,
      );
      await tester.pumpWidget(const AppStreaming());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-330, 0));
      await tester.pumpAndSettle();
      expect(action('Ver detalles de La última frecuencia'), findsOneWidget);

      await tester.tap(action('Buscar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'charge');
      await tester.pumpAndSettle();
      await tester.tap(action('Charge'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(action('Guardar en Biblioteca'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const AppStreaming());
      await tester.pumpAndSettle();
      await tester.tap(action('Biblioteca'));
      await tester.pumpAndSettle();
      expect(action('Charge'), findsOneWidget);
      await tester.tap(action('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Perfil local'), findsOneWidget);
    },
  );

  testWidgets(
    'La parrilla construye solo los resultados cercanos al viewport',
    (tester) async {
      final dependencies = AppDependencies.create();
      addTearDown(dependencies.dispose);
      final settings = AppSettings(dependencies.playbackPreferences);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        AppSettingsProvider(
          settings: settings,
          child: MaterialApp(
            home: HomeScreen(
              mediaRepository: _LargeCatalog(),
              addonRepository: dependencies.addons,
              iptvRepository: dependencies.iptv,
              resolveMovieStreams: dependencies.resolveMovieStreams,
              subtitles: dependencies.subtitles,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buscar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lote');
      await tester.pumpAndSettle();
      final mountedCards = find.byType(CatalogPoster, skipOffstage: false);
      expect(mountedCards.evaluate().length, lessThan(40));
      final distant = find.text('Lote 190');
      expect(distant, findsNothing);
      await tester.scrollUntilVisible(
        distant,
        440,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(distant, findsOneWidget);
      expect(mountedCards.evaluate().length, lessThan(40));
    },
  );

  testWidgets('Busca por título, género o tipo y combina pestañas y chips', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AppStreaming());
    await tester.pumpAndSettle();
    final cards = find.byType(CatalogPoster);
    List<String> titles() => tester
        .widgetList<CatalogPoster>(cards)
        .map((card) => card.media.title)
        .toList();
    Finder action(String label) => find.byWidgetPredicate(
      (widget) => widget is TvAction && widget.label == label,
    );

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
    await tester.enterText(field, 'ultima');
    await tester.pumpAndSettle();
    expect(titles(), ['La última frecuencia']);
    await tester.enterText(field, 'anime');
    await tester.pumpAndSettle();
    expect(titles(), ['Correo del cielo', 'El jardín de las luciérnagas']);
    await tester.enterText(field, 'ciencia ficcion');
    await tester.pumpAndSettle();
    expect(
      titles(),
      containsAll(['Charge', 'Tears of Steel', 'La última frecuencia']),
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(_focusedActionLabels(tester), ['Charge']);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(field, findsNothing);

    await tester.tap(action('Series'));
    await tester.pumpAndSettle();
    expect(titles(), [
      'La última frecuencia',
      'Correo del cielo',
      'Estación Mareas',
    ]);
    await tester.tap(action('Filtrar por Drama'));
    await tester.pumpAndSettle();
    expect(titles(), ['La última frecuencia', 'Estación Mareas']);
    await tester.tap(action('Dibujos'));
    await tester.pumpAndSettle();
    expect(titles(), contains('Big Buck Bunny'));
    expect(titles(), isNot(contains('Charge')));
  });

  testWidgets(
    'Activa IPTV, importa y reproduce un canal con el mando, y oculta el acceso al desactivar',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      var playlistRequests = 0;
      final dependencies = AppDependencies.create(
        MockClient((request) async {
          expect(request.url.path, '/canales.m3u8');
          playlistRequests++;
          return http.Response(
            '#EXTM3U\n#EXTINF:-1,Canal de prueba\nhttps://example.com/vivo.m3u8',
            200,
          );
        }),
      );
      addTearDown(dependencies.dispose);
      final settings = AppSettings(dependencies.playbackPreferences);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        AppSettingsProvider(
          settings: settings,
          child: MaterialApp(
            home: HomeScreen(
              mediaRepository: dependencies.media,
              addonRepository: dependencies.addons,
              iptvRepository: dependencies.iptv,
              resolveMovieStreams: dependencies.resolveMovieStreams,
              subtitles: dependencies.subtitles,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final liveAccess = find.byTooltip('TV en vivo');
      expect(liveAccess, findsNothing);

      Future<void> tapVisible(Finder target) async {
        await _reveal(tester, target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('Complementos VOD'), findsOneWidget);
      final iptvHeading = find.text('IPTV / Canales en vivo');
      await _reveal(tester, iptvHeading);
      expect(iptvHeading, findsOneWidget);
      final enabled = find.widgetWithText(SwitchListTile, 'Activar IPTV');
      await tapVisible(enabled);
      expect(await dependencies.playbackPreferences.getIptvEnabled(), isTrue);
      await tapVisible(find.widgetWithText(FilledButton, 'Agregar lista'));
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/canales.m3u8',
      );
      await tester.pump();
      final confirm = find.widgetWithText(FilledButton, 'Agregar');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      expect(playlistRequests, 1);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      final imported = find.text('Canales: 1');
      await _reveal(tester, imported);
      expect(imported, findsOneWidget);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(liveAccess, findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      for (var step = 0; step < 6; step++) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(_focusedActionLabels(tester), ['TV en vivo']);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('Canal de prueba'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedActionLabels(tester), ['Reproducir Canal de prueba']);
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.single, 'https://example.com/vivo.m3u8');
      expect(find.text('En vivo'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);

      await _press(tester, LogicalKeyboardKey.select);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Complementos'));
      await tester.pumpAndSettle();
      await tapVisible(enabled);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(liveAccess, findsNothing);
      expect(await dependencies.playbackPreferences.getIptvEnabled(), isFalse);
      expect((await dependencies.iptv.list()).single.channels, hasLength(1));
    },
  );

  testWidgets(
    'Abre directamente la fuente prioritaria y permite ajustar la calidad con el mando',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);

      await tester.pumpWidget(const AppStreaming());
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedActionLabels(tester), ['Reproducir Charge']);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
      expect(
        tester.widget<PlayerScreen>(find.byType(PlayerScreen)).source.quality,
        '1080p',
      );
      expect(player.played, 1);

      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.played, 2);
      expect(player.sources.last, endsWith('-720.mp4'));

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd?.call(37000);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle();
      expect(_focusedActionLabels(tester), ['Manual']);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('Resolución manual'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.last, endsWith('-1080.mp4'));
      expect(player.positions[3], const Duration(seconds: 37));
      expect(player.played, 3);

      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('Auto · 1080p'), findsOneWidget);
      expect(player.played, 3);

      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle();
      expect(_focusedActionLabels(tester), ['Automático']);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.last, endsWith('-720.mp4'));
      expect(find.text('Auto · 720p'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Actualiza la ficha y permite elegir una fuente de Torrentio con el mando',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      var torrentioQueries = 0;
      final dependencies = AppDependencies.create(
        MockClient((request) async {
          expect(request.url.path, '/stream/movie/tt1254207.json');
          torrentioQueries++;
          return http.Response(r'''
            {"streams":[
              {"name":"4K","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2},
              {"name":"1080p","url":"https://example.com/torrentio-1080.mp4"},
              {"name":"720p","url":"https://example.com/torrentio-720.mp4"}
            ]}
          ''', 200);
        }),
      );
      addTearDown(dependencies.dispose);
      final settings = AppSettings(dependencies.playbackPreferences);
      addTearDown(settings.dispose);
      final catalog = await dependencies.media.browse(
        MediaCollection.popularMovies,
      );
      final bunny = catalog.singleWhere(
        (movie) => movie.title == 'Big Buck Bunny',
      );
      expect(bunny.imdbId, 'tt1254207');

      await tester.pumpWidget(
        AppSettingsProvider(
          settings: settings,
          child: MaterialApp(
            home: DetailScreen(
              media: bunny,
              mediaRepository: dependencies.media,
              addonRepository: dependencies.addons,
              iptvRepository: dependencies.iptv,
              resolveMovieStreams: dependencies.resolveMovieStreams,
              subtitles: const _TestSubtitles(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final detail = tester.state(find.byType(DetailScreen));
      expect(find.text('Ver enlaces'), findsNothing);
      expect(torrentioQueries, 0);

      Future<void> openSettings() async {
        await tester.tap(find.byTooltip('Complementos'));
        await tester.pumpAndSettle();
      }

      Future<void> toggle(String title) async {
        final tile = find.widgetWithText(SwitchListTile, title);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }

      Future<void> closeSettings() async {
        await tester.tap(find.byTooltip('Volver').last);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(DetailScreen)), same(detail));
      }

      await openSettings();
      await toggle('Modo desarrollador');
      expect(find.text('Ver enlaces', skipOffstage: false), findsOneWidget);
      await closeSettings();
      expect(torrentioQueries, 0);
      final inactive = find.text(
        'Activa Torrentio en Complementos para consultar sus enlaces.',
      );
      await _reveal(tester, inactive);
      expect(inactive, findsOneWidget);

      await openSettings();
      await toggle('Torrentio');
      await closeSettings();
      expect(torrentioQueries, 1);
      final magnet = find.textContaining(
        'BitTorrent · Índice de archivo 2 · Sin reproducción directa',
      );
      await _reveal(tester, magnet);
      expect(magnet, findsOneWidget);
      final showLinks = find.byWidgetPredicate(
        (widget) => widget is TvAction && widget.label == 'Ver enlaces',
        skipOffstage: false,
      );
      await Scrollable.ensureVisible(
        tester.element(showLinks),
        alignment: 0.35,
      );
      await tester.pumpAndSettle();
      await tester.tap(showLinks);
      await tester.pumpAndSettle();
      expect(_focusedActionLabels(tester).single, startsWith('1080p'));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedActionLabels(tester).single, startsWith('720p'));
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.single, 'https://example.com/torrentio-720.mp4');

      await _press(tester, LogicalKeyboardKey.select);
      expect(find.byType(PlayerScreen), findsNothing);
      await openSettings();
      await toggle('Modo desarrollador');
      expect(find.text('Ver enlaces', skipOffstage: false), findsNothing);
      await closeSettings();
      expect(find.text('Ver enlaces'), findsNothing);
      expect(find.textContaining('Enlaces de reproducción'), findsNothing);
      expect(torrentioQueries, 1);
    },
  );

  testWidgets(
    'El menú manual permite elegir 4K y 8K con una ventana y pantalla reducidas',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      tester.view.display.size = const Size(1600, 900);
      addTearDown(tester.view.display.resetSize);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);

      final sources = [
        for (final quality in ['480p', '720p', '1080p', '4K', '8K'])
          StreamOption(
            quality: quality,
            url: Uri.https('example.com', '/$quality.mp4'),
            providerId: 'demo',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            title: 'Prueba de pantalla',
            source: sources[1],
            sources: sources,
            providerNames: const {'demo': 'Video de prueba'},
            subtitles: const _TestSubtitles(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> openManual() async {
        await tester.tap(find.byTooltip('Calidad'));
        await tester.pumpAndSettle();
        expect(_focusedActionLabels(tester), ['Manual']);
        await _press(tester, LogicalKeyboardKey.select);
      }

      await openManual();
      final options = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TvAction),
      );
      expect(
        tester.widgetList<TvAction>(options).map((action) => action.label),
        contains('720p · Video de prueba'),
      );
      expect(_focusedActionLabels(tester), ['720p · Video de prueba']);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focusedActionLabels(tester), ['4K · Video de prueba']);

      tester.view.display.size = const Size(1280, 720);
      tester.view.physicalSize = const Size(530, 400);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.last, sources[3].url.toString());

      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      await openManual();
      expect(_focusedActionLabels(tester), ['4K · Video de prueba']);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.sources.last, sources[4].url.toString());
    },
  );

  testWidgets('Abandona un arranque lento y muestra el búfer del respaldo', (
    tester,
  ) async {
    final initial = StreamOption(
      quality: '1080p',
      url: Uri.https('example.com', '/lento.mp4'),
      providerId: 'torrentio',
    );
    final backup = StreamOption(
      quality: '720p',
      url: Uri.https('example.com', '/respaldo.mp4'),
      providerId: 'torrentio',
    );
    final initialEvents = StreamController<VideoEvent>(
      sync: true,
      onCancel: () async {},
    );
    final backupEvents = StreamController<VideoEvent>(
      sync: true,
      onCancel: () async {},
    );
    final original = VideoPlayerPlatform.instance;
    final player = _TestVideoPlayer(
      events: {
        initial.url.toString(): initialEvents.stream,
        backup.url.toString(): backupEvents.stream,
      },
    );
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          title: 'Prueba de inicio',
          source: initial,
          sources: [initial, backup],
          providerNames: const {'torrentio': 'Torrentio'},
          subtitles: const _TestSubtitles(),
          automaticStartup: true,
        ),
      ),
    );
    expect(find.text('Conectando con la fuente…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(player.sources, [initial.url.toString(), backup.url.toString()]);
    expect(player.disposed, [1]);
    expect(find.text('Probando otra fuente…'), findsOneWidget);

    backupEvents.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 4),
        size: const Size(1280, 720),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.played, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    backupEvents.add(VideoEvent(eventType: VideoEventType.bufferingStart));
    await tester.pump();
    expect(find.text('Cargando video…'), findsOneWidget);
    backupEvents.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(initialEvents.close());
    unawaited(backupEvents.close());
    await tester.pump();
    expect(player.disposed, [1, 2]);
  });

  testWidgets(
    'Libera la pantalla al pausar, suspender o salir del reproductor',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final changes = <bool>[];
      final power = PowerManagementService(
        wakeLock: (enabled) async => changes.add(enabled),
      );
      addTearDown(power.dispose);
      final source = StreamOption(
        quality: '720p',
        url: Uri.https('example.com', '/energia.mp4'),
        providerId: 'demo',
      );
      await tester.pumpWidget(
        PowerManagementScope(
          service: power,
          child: MaterialApp(
            home: PlayerScreen(
              title: 'Energía',
              source: source,
              sources: [source],
              providerNames: const {},
              subtitles: const _TestSubtitles(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes, [true]);
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      await tester.tap(find.byTooltip('Reproducir video'));
      await tester.pumpAndSettle();
      expect(changes, [true, false, true]);
      final pausesBeforeBackground = player.paused;
      power.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(changes.last, isFalse);
      expect(player.paused, pausesBeforeBackground + 1);
      power.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(player.played, 2);
      await tester.tap(find.byTooltip('Reproducir video'));
      await tester.pumpAndSettle();
      expect(changes.last, isTrue);
      power.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pumpAndSettle();
      expect(changes.last, isFalse);
      power.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(player.played, 3);
      await tester.tap(find.byTooltip('Reproducir video'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(changes, [true, false, true, false, true, false, true, false]);
    },
  );

  testWidgets(
    'Libera una carga pendiente y espera la acción del usuario al volver',
    (tester) async {
      final source = StreamOption(
        quality: '720p',
        url: Uri.https('example.com', '/inicio-pendiente.mp4'),
        providerId: 'demo',
      );
      final pending = StreamController<VideoEvent>(
        sync: true,
        onCancel: () async {},
      );
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer(
        events: {source.url.toString(): pending.stream},
      );
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final changes = <bool>[];
      final power = PowerManagementService(
        wakeLock: (enabled) async => changes.add(enabled),
      );
      addTearDown(power.dispose);
      await tester.pumpWidget(
        PowerManagementScope(
          service: power,
          child: MaterialApp(
            home: PlayerScreen(
              title: 'Carga',
              source: source,
              sources: [source],
              providerNames: const {},
              subtitles: const _TestSubtitles(),
            ),
          ),
        ),
      );
      expect(player.sources, [source.url.toString()]);
      power.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(player.disposed, [1]);
      expect(changes, isEmpty);
      power.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(player.sources, hasLength(1));
      player.events.remove(source.url.toString());
      await tester.tap(find.byTooltip('Reproducir video'));
      await tester.pumpAndSettle();
      expect(player.sources, hasLength(2));
      expect(player.played, 1);
      expect(changes, [true]);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(pending.close());
    },
  );

  testWidgets(
    'Cierra también el controlador de un cambio de calidad pendiente',
    (tester) async {
      final initial = StreamOption(
        quality: '1080p',
        url: Uri.https('example.com', '/actual.mp4'),
        providerId: 'demo',
      );
      final next = StreamOption(
        quality: '720p',
        url: Uri.https('example.com', '/pendiente.mp4'),
        providerId: 'demo',
      );
      final activeEvents = StreamController<VideoEvent>(
        sync: true,
        onCancel: () async {},
      );
      final events = StreamController<VideoEvent>(
        sync: true,
        onCancel: () async {},
      );
      final original = VideoPlayerPlatform.instance;
      final player = _TestVideoPlayer(
        events: {
          initial.url.toString(): activeEvents.stream,
          next.url.toString(): events.stream,
        },
      );
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            title: 'Cambio de calidad',
            source: initial,
            sources: [initial, next],
            providerNames: const {'demo': 'Demo'},
            subtitles: const _TestSubtitles(),
          ),
        ),
      );
      activeEvents.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 4),
          size: const Size(1920, 1080),
        ),
      );
      await tester.pumpAndSettle();
      expect(player.played, 1);
      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.sources, [initial.url.toString(), next.url.toString()]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(player.disposed, unorderedEquals([1, 2]));
      unawaited(activeEvents.close());
      unawaited(events.close());
    },
  );

  testWidgets('Selecciona audio y activa o desactiva subtítulos WebVTT', (
    tester,
  ) async {
    final original = VideoPlayerPlatform.instance;
    final player = _TestVideoPlayer();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final captionUrl = Uri.parse('https://example.com/captions.vtt');
    final source = StreamOption(
      quality: '720p',
      url: Uri.parse('https://example.com/video.mp4'),
      providerId: 'demo',
      subtitles: [
        SubtitleTrack(url: captionUrl, language: 'es', label: 'Español CC'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          title: 'Prueba',
          source: source,
          sources: [source],
          providerNames: const {},
          subtitles: const _TestSubtitles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Audio'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.audioSelection, 'es');

    await tester.tap(find.byTooltip('Subtítulos'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Subtítulo de prueba'), findsOneWidget);

    await tester.tap(find.byTooltip('Subtítulos'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Subtítulo de prueba'), findsNothing);
  });
}

final class _LargeCatalog implements MediaRepository {
  @override
  Future<List<MediaItem>> browse(MediaCollection collection) async => [
    if (collection == MediaCollection.popularMovies)
      for (var index = 1; index <= 220; index++)
        MediaItem(
          id: '$index',
          kind: MediaKind.movie,
          title: 'Lote $index',
          overview: '',
          posterPath: null,
        ),
  ];

  @override
  Future<MediaItem> details(MediaItem media) async => media;

  @override
  Future<List<MediaItem>> search({
    required String query,
    required MediaKind kind,
    int page = 1,
  }) async => [];
}

final class _TestSubtitles implements SubtitleRepository {
  const _TestSubtitles();

  @override
  Future<String> read(SubtitleTrack track) async =>
      'WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nSubtítulo de prueba\n';
}

final class _TestVideoPlayer extends VideoPlayerPlatform {
  _TestVideoPlayer({this.events = const {}});

  final Map<String, Stream<VideoEvent>> events;
  final sources = <String?>[];
  final disposed = <int>[];
  final positions = <int, Duration>{};
  int played = 0;
  int paused = 0;
  String? audioSelection;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    sources.add(dataSource.uri);
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      events[sources[playerId - 1]] ??
      Stream.value(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 4),
          size: const Size(1920, 1080),
        ),
      );

  @override
  Future<void> play(int playerId) async => played++;

  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);

  @override
  Future<void> pause(int playerId) async => paused++;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async => [
    VideoAudioTrack(
      id: 'en',
      label: 'Inglés',
      language: 'en',
      isSelected: audioSelection != 'es',
    ),
    VideoAudioTrack(
      id: 'es',
      label: 'Español',
      language: 'es',
      isSelected: audioSelection == 'es',
    ),
  ];

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {
    audioSelection = trackId;
  }
}

List<String> _focusedActionLabels(WidgetTester tester) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .where((widget) => widget.properties.focused ?? false)
      .map((widget) => widget.properties.label)
      .whereType<String>()
      .toList();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}
