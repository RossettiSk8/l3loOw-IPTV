import 'dart:math' as math;

// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/addon_repository.dart';
import '../../domain/contracts/iptv_repository.dart';
import '../../domain/contracts/media_repository.dart';
import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/browse_catalog.dart';
import '../../domain/repositories/list_live_channels.dart';
import '../../domain/repositories/resolve_movie_streams.dart';
import '../widgets/app_settings_provider.dart';
import '../widgets/home_catalog.dart';
import '../widgets/mobile_catalog.dart';
import '../widgets/mobile_catalog_navigation.dart';
import '../widgets/streaming_theme.dart';
import '../widgets/tv_action.dart';
import 'addons_config_screen.dart';
import 'detail_screen.dart';
import 'live_tv_screen.dart';
import 'player_screen.dart';

const _sections = [
  CatalogFilter.all,
  CatalogFilter.premieres,
  CatalogFilter.series,
  CatalogFilter.movies,
  CatalogFilter.anime,
  CatalogFilter.cartoons,
];
const _filters = [
  CatalogFilter.all,
  CatalogFilter.premieres,
  CatalogFilter.action,
  CatalogFilter.drama,
  CatalogFilter.scienceFiction,
  CatalogFilter.comedy,
  CatalogFilter.anime,
  CatalogFilter.cartoons,
];

String _label(CatalogFilter category) => switch (category) {
  CatalogFilter.all => 'Todos',
  CatalogFilter.premieres => 'Estrenos',
  CatalogFilter.series => 'Series',
  CatalogFilter.movies => 'Películas',
  CatalogFilter.action => 'Acción',
  CatalogFilter.drama => 'Drama',
  CatalogFilter.scienceFiction => 'Ciencia ficción',
  CatalogFilter.comedy => 'Comedia',
  CatalogFilter.anime => 'Anime',
  CatalogFilter.cartoons => 'Dibujos',
};

final class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.mediaRepository,
    required this.addonRepository,
    required this.iptvRepository,
    required this.resolveMovieStreams,
    required this.subtitles,
    super.key,
  });

  final MediaRepository mediaRepository;
  final AddonRepository addonRepository;
  final IptvRepository iptvRepository;
  final ResolveMovieStreams resolveMovieStreams;
  final SubtitleRepository subtitles;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _settingsFocus = FocusNode(debugLabel: 'Ajustes');
  final _searchButton = FocusNode(debugLabel: 'Buscar');
  final _searchField = FocusNode(debugLabel: 'Campo de búsqueda');
  final _play = FocusNode(debugLabel: 'Reproducir destacado');
  final _details = FocusNode(debugLabel: 'Detalles del destacado');
  final _firstResult = FocusNode(debugLabel: 'Primer resultado');
  final _searchText = TextEditingController();
  final _scroll = ScrollController();
  final _navigation = {
    for (final item in _sections)
      item: FocusNode(debugLabel: 'Pestaña ${item.name}'),
  };
  final _chips = {
    for (final item in _filters)
      item: FocusNode(debugLabel: 'Filtro ${item.name}'),
  };
  final _live = FocusNode(debugLabel: 'TV en vivo');

  late Future<List<MediaItem>> _catalog = _browser.load();
  CatalogFilter _section = CatalogFilter.all;
  MobileDestination _destination = MobileDestination.home;
  CatalogFilter _genre = CatalogFilter.all;
  String _query = '';
  bool _searchOpen = false;
  bool _opening = false;

  BrowseCatalog get _browser => BrowseCatalog(widget.mediaRepository);

  late final _traversal = _CatalogTraversal(_focusTarget);

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaRepository != widget.mediaRepository) {
      _catalog = _browser.load();
    }
  }

  @override
  void dispose() {
    for (final node in [
      _settingsFocus,
      _searchButton,
      _searchField,
      _play,
      _details,
      _firstResult,
      _live,
      ..._navigation.values,
      ..._chips.values,
    ]) {
      node.dispose();
    }
    _searchText.dispose();
    _scroll.dispose();
    super.dispose();
  }

  FocusNode? _focusTarget(FocusNode current, TraversalDirection direction) {
    if (isCompactStreamingLayout(MediaQuery.sizeOf(context))) {
      if (direction == TraversalDirection.down) {
        if (current == _settingsFocus && _details.context != null) {
          return _details;
        }
        if (current == _details) return _firstResult;
      }
      if (direction == TraversalDirection.up &&
          current == _firstResult &&
          _details.context != null) {
        return _details;
      }
      return null;
    }
    if (current == _play && direction == TraversalDirection.right) {
      return _details;
    }
    if (current == _details && direction == TraversalDirection.left) {
      return _play;
    }
    final nav = _navigation[_section]!;
    final chip = _chips[_genre]!;
    if (direction == TraversalDirection.down) {
      if (current == _settingsFocus || current == _searchButton) {
        return _searchOpen ? _searchField : nav;
      }
      if (_navigation.containsValue(current) || current == _live) {
        return _searchOpen
            ? _searchField
            : (_play.context != null ? _play : chip);
      }
      if (current == _searchField || current == _play || current == _details) {
        return chip;
      }
      if (_chips.containsValue(current)) return _firstResult;
    }
    if (direction == TraversalDirection.up) {
      if (current == _firstResult) return chip;
      if (_chips.containsValue(current)) {
        return _searchOpen
            ? _searchField
            : (_play.context != null ? _play : nav);
      }
      if (current == _play || current == _details || current == _searchField) {
        return nav;
      }
      if (_navigation.containsValue(current) || current == _live) {
        return _settingsFocus;
      }
    }
    return null;
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _selectSection(CatalogFilter category) {
    _scrollToTop();
    setState(() {
      _section = category;
      _genre = CatalogFilter.all;
    });
  }

  void _setQuery(String value) {
    _scrollToTop();
    setState(() => _query = value);
  }

  void _selectGenre(CatalogFilter genre) {
    _scrollToTop();
    setState(() => _genre = genre);
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _searchButton.requestFocus();
      _searchText.clear();
      _scrollToTop();
      setState(() {
        _searchOpen = false;
        _query = '';
      });
      return;
    }
    setState(() => _searchOpen = true);
    _searchField.requestFocus();
  }

  void _openAddons() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddonsConfigScreen(
          repository: widget.addonRepository,
          iptvRepository: widget.iptvRepository,
        ),
      ),
    );
  }

  void _openLiveTv() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LiveTvScreen(
          listChannels: ListLiveChannels(widget.iptvRepository),
          subtitles: widget.subtitles,
        ),
      ),
    );
  }

  void _showDetails(MediaItem media) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          media: media,
          mediaRepository: widget.mediaRepository,
          resolveMovieStreams: widget.resolveMovieStreams,
          subtitles: widget.subtitles,
          addonRepository: widget.addonRepository,
          iptvRepository: widget.iptvRepository,
        ),
      ),
    );
  }

  Future<void> _playFeatured(MediaItem media) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final result = await widget.resolveMovieStreams.preferred(media);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final source = result.preferredOption;
      if (source == null) {
        _showPlaybackUnavailable();
      } else {
        await PlayerScreen.openMedia(
          context,
          title: media.title,
          source: source,
          result: result,
          subtitles: widget.subtitles,
          automaticStartup: true,
        );
      }
    } catch (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _showPlaybackUnavailable();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showPlaybackUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No hay reproducción disponible para este título.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = isCompactStreamingLayout(MediaQuery.sizeOf(context));
    final inlineNavigation = width >= 1100;
    final showLiveTv = AppSettingsProvider.of(context).iptvEnabled;
    if (compact) {
      return FocusTraversalGroup(
        policy: _traversal,
        child: _buildMobile(showLiveTv),
      );
    }
    final inset = (width * .043).clamp(28.0, 72.0);
    final navigation = _buildNavigation(showLiveTv);
    return CallbackShortcuts(
      bindings: {
        if (_searchOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _toggleSearch,
      },
      child: FocusTraversalGroup(
        policy: _traversal,
        child: Scaffold(
          backgroundColor: StreamingPalette.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: StreamingPalette.background,
                    border: Border(
                      bottom: BorderSide(color: StreamingPalette.divider),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, 4, inset, 5),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 65,
                          child: Row(
                            children: [
                              if (inlineNavigation) ...[
                                const _Brand(),
                                const SizedBox(width: 18),
                                Expanded(child: navigation),
                              ] else
                                const Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _Brand(),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              _TopButton(
                                tooltip: _searchOpen
                                    ? 'Cerrar búsqueda'
                                    : 'Buscar',
                                icon: _searchOpen
                                    ? Icons.close
                                    : Icons.search_rounded,
                                focusNode: _searchButton,
                                onPressed: _toggleSearch,
                              ),
                              const SizedBox(width: 8),
                              _TopButton(
                                tooltip: 'Complementos',
                                semantics: 'Abrir complementos',
                                icon: Icons.settings_outlined,
                                focusNode: _settingsFocus,
                                autofocus: true,
                                onPressed: _openAddons,
                              ),
                            ],
                          ),
                        ),
                        if (!inlineNavigation) navigation,
                        if (_searchOpen) _buildSearch(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<MediaItem>>(
                    future: _catalog,
                    builder: (context, snapshot) =>
                        _buildCatalog(snapshot, inset, false, width),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectDestination(MobileDestination destination) {
    _scrollToTop();
    setState(() => _destination = destination);
  }

  Widget _buildMobile(bool showLiveTv) {
    final settings = AppSettingsProvider.of(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final narrowHeight = MediaQuery.sizeOf(context).height < 500;
    return Scaffold(
      backgroundColor: StreamingPalette.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                if (!keyboardVisible || !narrowHeight)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 7),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _Brand(),
                          ),
                        ),
                        if (showLiveTv) ...[
                          _TopButton(
                            tooltip: 'TV en vivo',
                            icon: Icons.live_tv_outlined,
                            focusNode: _live,
                            onPressed: _openLiveTv,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _TopButton(
                          tooltip: 'Complementos',
                          semantics: 'Abrir complementos',
                          icon: Icons.settings_outlined,
                          focusNode: _settingsFocus,
                          autofocus: true,
                          onPressed: _openAddons,
                        ),
                      ],
                    ),
                  ),
                if (_destination == MobileDestination.search)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _buildSearch(),
                  ),
                Expanded(
                  child: switch (_destination) {
                    MobileDestination.library => _mobileLibrary(settings),
                    MobileDestination.profile => _mobileProfile(),
                    MobileDestination.home ||
                    MobileDestination.search => FutureBuilder<List<MediaItem>>(
                      future: _catalog,
                      builder: (context, snapshot) =>
                          _buildMobileCatalog(snapshot),
                    ),
                  },
                ),
              ],
            ),
            if (!keyboardVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MobileCatalogNavigation(
                  selected: _destination,
                  onSelected: _selectDestination,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _catalogScroll(List<Widget> slivers, {bool mobile = false}) =>
      CustomScrollView(
        controller: _scroll,
        slivers: [
          ...slivers,
          SliverToBoxAdapter(
            child: SizedBox(
              height: mobile ? 89 + MediaQuery.paddingOf(context).bottom : 40,
            ),
          ),
        ],
      );

  Widget _mobileLibrary(AppSettings settings) => _catalogScroll([
    const SliverToBoxAdapter(child: SizedBox(height: 22)),
    if (settings.savedTitles.isEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ShelfHeading('Biblioteca'),
              const SizedBox(height: 12),
              Text(
                settings.libraryReady
                    ? 'Guarda títulos desde el menú de su ficha para verlos aquí.'
                    : 'La biblioteca no está disponible.',
                style: const TextStyle(color: StreamingPalette.muted),
              ),
            ],
          ),
        ),
      )
    else
      ..._buildResults(settings.savedTitles, 'Biblioteca', 18),
  ], mobile: true);

  Widget _mobileProfile() => _catalogScroll([
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ShelfHeading('Perfil'),
            const SizedBox(height: 14),
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline_rounded),
              ),
              title: const Text('Perfil local'),
              subtitle: const Text('Ajustes y biblioteca de este dispositivo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAddons,
            ),
          ],
        ),
      ),
    ),
  ], mobile: true);

  Widget _buildMobileCatalog(AsyncSnapshot<List<MediaItem>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done || snapshot.hasError) {
      return _buildCatalog(
        snapshot,
        18,
        true,
        MediaQuery.sizeOf(context).width,
      );
    }
    final items = snapshot.data!;
    if (_destination == MobileDestination.search) {
      final view = _browser.view(
        items,
        section: CatalogFilter.all,
        genre: CatalogFilter.all,
        query: _query,
      );
      final results = view.results;
      return _catalogScroll([
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (results == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Escribe para explorar el catálogo.',
                style: TextStyle(color: StreamingPalette.muted),
              ),
            ),
          )
        else
          ..._buildResults(results, 'Resultados de búsqueda', 18),
      ], mobile: true);
    }
    final highlights = _browser.highlights(items);
    final rails = _browser
        .trendingRails(items)
        .where((rail) => rail.items.isNotEmpty)
        .toList(growable: false);
    return _catalogScroll([
      SliverToBoxAdapter(
        child: highlights.isNotEmpty
            ? MobileCatalogHero(
                items: highlights,
                detailsFocus: _details,
                onDetails: _showDetails,
              )
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay títulos disponibles.',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 15)),
      SliverList.builder(
        itemCount: rails.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) {
          final rail = rails[index];
          return _buildRail(
            rail,
            18,
            120,
            first: index == 0,
            title: rail.category == CatalogFilter.movies
                ? 'Trending Movies'
                : 'Trending Series',
            showYear: true,
          );
        },
      ),
    ], mobile: true);
  }

  Widget _buildNavigation(bool showLiveTv) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      spacing: 4,
      children: [
        for (final section in _sections)
          _Selector(
            label: section == CatalogFilter.all ? 'Inicio' : _label(section),
            selected: _section == section,
            focusNode: _navigation[section]!,
            onPressed: () => _selectSection(section),
          ),
        if (showLiveTv)
          Tooltip(
            message: 'TV en vivo',
            excludeFromSemantics: true,
            child: _Selector(
              label: 'TV en Vivo',
              semantics: 'TV en vivo',
              selected: false,
              focusNode: _live,
              onPressed: _openLiveTv,
              icon: Icons.live_tv_outlined,
            ),
          ),
      ],
    ),
  );

  Widget _buildSearch() => Padding(
    padding: const EdgeInsets.only(top: 7, bottom: 9),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: TextField(
          controller: _searchText,
          focusNode: _searchField,
          onChanged: _setQuery,
          onSubmitted: (_) {
            if (_firstResult.context != null) {
              FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
                _firstResult,
              );
            } else {
              _chips[_genre]!.requestFocus();
            }
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Buscar por título, género o tipo',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: StreamingPalette.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ),
  );

  Widget _buildCatalog(
    AsyncSnapshot<List<MediaItem>> snapshot,
    double inset,
    bool compact,
    double width,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Cargando catálogo'),
      );
    }
    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No se pudo cargar el catálogo.'),
            TextButton(
              onPressed: () {
                setState(() {
                  _catalog = _browser.load();
                });
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    final query = _searchOpen ? _query : '';
    final view = _browser.view(
      snapshot.data!,
      section: _section,
      genre: _genre,
      query: query,
    );
    final featured = view.featured;
    final results = view.results;
    final cardWidth = (width * .133).clamp(122.0, 190.0);
    final heading = query.trim().isNotEmpty
        ? 'Resultados de búsqueda'
        : _genre != CatalogFilter.all
        ? _label(_genre)
        : _label(_section);

    return _catalogScroll([
      SliverToBoxAdapter(
        child: featured != null
            ? CatalogHero(
                media: featured,
                inset: inset,
                compact: compact,
                playFocus: _play,
                detailsFocus: _details,
                isOpening: _opening,
                onPlay: () => _playFeatured(featured),
                onDetails: () => _showDetails(featured),
              )
            : const SizedBox(height: 20),
      ),
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: inset, vertical: 4),
          child: Row(
            spacing: 8,
            children: [
              for (final filter in _filters)
                _Selector(
                  label: _label(filter),
                  semantics: 'Filtrar por ${_label(filter)}',
                  selected: _genre == filter,
                  focusNode: _chips[filter]!,
                  pill: true,
                  onPressed: () => _selectGenre(filter),
                ),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
      if (results != null)
        ..._buildResults(results, heading, inset)
      else if (view.rails.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No hay títulos disponibles.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: view.rails.length,
          addAutomaticKeepAlives: false,
          itemBuilder: (context, index) => _buildRail(
            view.rails[index],
            inset,
            cardWidth,
            first: index == 0,
          ),
        ),
    ]);
  }

  Widget _buildRail(
    CatalogRail rail,
    double inset,
    double width, {
    required bool first,
    String? title,
    bool showYear = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: _ShelfHeading(
            title ??
                (rail.category == CatalogFilter.drama
                    ? 'Dramas'
                    : _label(rail.category)),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height:
              CatalogPoster.heightFor(context, width, showYear: showYear) + 18,
          child: ListView.separated(
            key: PageStorageKey(rail.category),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: inset, vertical: 9),
            itemCount: rail.items.length,
            addAutomaticKeepAlives: false,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) => _poster(
              rail.items[index],
              width,
              focus: first && index == 0 ? _firstResult : null,
              showYear: showYear,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _buildResults(
    List<MediaItem> items,
    String heading,
    double inset,
  ) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 14),
        child: _ShelfHeading(heading),
      ),
    ),
    SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      sliver: items.isEmpty
          ? const SliverToBoxAdapter(
              child: Text(
                'No hay títulos que coincidan.',
                style: TextStyle(color: StreamingPalette.muted),
              ),
            )
          : SliverLayoutBuilder(
              builder: (context, constraints) {
                const gap = 14.0;
                final available = constraints.crossAxisExtent;
                final columns = math.max(1, ((available + gap) / 142).floor());
                final width = (available - (columns - 1) * gap) / columns;
                return SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    mainAxisExtent: CatalogPoster.heightFor(
                      context,
                      width,
                      showYear: false,
                    ),
                  ),
                  itemCount: items.length,
                  addAutomaticKeepAlives: false,
                  itemBuilder: (context, index) => _poster(
                    items[index],
                    width,
                    focus: index == 0 ? _firstResult : null,
                  ),
                );
              },
            ),
    ),
  ];

  Widget _poster(
    MediaItem item,
    double width, {
    FocusNode? focus,
    bool showYear = false,
  }) => CatalogPoster(
    key: ValueKey((item.kind, item.id)),
    media: item,
    width: width,
    onPressed: () => _showDetails(item),
    focusNode: focus,
    showYear: showYear,
  );
}

class _CatalogTraversal extends WidgetOrderTraversalPolicy {
  _CatalogTraversal(this.targetFor);

  final FocusNode? Function(FocusNode, TraversalDirection) targetFor;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final target = targetFor(currentNode, direction);
    if (target != null && target.context != null) {
      requestFocusCallback(target);
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: StreamingPalette.accent,
          borderRadius: BorderRadius.all(Radius.circular(9)),
        ),
        child: SizedBox.square(
          dimension: 35,
          child: Icon(
            Icons.play_arrow_rounded,
            size: 27,
            color: StreamingPalette.background,
          ),
        ),
      ),
      SizedBox(width: 9),
      Flexible(
        child: Text(
          'l3loOw',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -.4,
          ),
        ),
      ),
    ],
  );
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.tooltip,
    required this.icon,
    required this.focusNode,
    required this.onPressed,
    this.semantics,
    this.autofocus = false,
  });

  final String tooltip;
  final IconData icon;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final String? semantics;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: TvAction(
      label: semantics ?? tooltip,
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      radius: 9,
      child: SizedBox.square(
        dimension: 44,
        child: ColoredBox(
          color: StreamingPalette.surface,
          child: Icon(icon, size: 21, color: Colors.white),
        ),
      ),
    ),
  );
}

class _Selector extends StatelessWidget {
  const _Selector({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    this.semantics,
    this.pill = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final String? semantics;
  final bool pill;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? StreamingPalette.accent
        : StreamingPalette.muted;
    return TvAction(
      label: semantics ?? label,
      focusNode: focusNode,
      selected: selected,
      radius: pill ? 22 : 7,
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pill
              ? (selected ? StreamingPalette.raised : StreamingPalette.surface)
              : Colors.transparent,
          border: pill
              ? Border.all(
                  color: selected
                      ? StreamingPalette.outline
                      : StreamingPalette.divider,
                )
              : Border(
                  bottom: BorderSide(
                    color: selected
                        ? StreamingPalette.accent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: pill ? 15 : 10,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: foreground, size: 16),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfHeading extends StatelessWidget {
  const _ShelfHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 23,
        letterSpacing: -.35,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
