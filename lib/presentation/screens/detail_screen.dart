// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/contracts/addon_repository.dart';
import '../../domain/contracts/iptv_repository.dart';
import '../../domain/contracts/media_repository.dart';
import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/stream_chain_result.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/repositories/resolve_movie_streams.dart';
import '../widgets/app_settings_provider.dart';
import '../widgets/detail_media_header.dart';
import '../widgets/home_catalog.dart';
import '../widgets/streaming_theme.dart';
import '../widgets/tv_action.dart';
import 'addons_config_screen.dart';
import 'player_screen.dart';

final class DetailScreen extends StatefulWidget {
  const DetailScreen({
    required this.media,
    required this.mediaRepository,
    required this.addonRepository,
    required this.iptvRepository,
    required this.resolveMovieStreams,
    required this.subtitles,
    super.key,
  });

  final MediaItem media;
  final MediaRepository mediaRepository;
  final AddonRepository addonRepository;
  final IptvRepository iptvRepository;
  final ResolveMovieStreams resolveMovieStreams;
  final SubtitleRepository subtitles;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _links = GlobalKey();
  final _firstSource = FocusNode(debugLabel: 'Primer enlace de reproducción');
  final _play = FocusNode(debugLabel: 'Reproducir');
  late final _details = widget.mediaRepository.details(widget.media);
  Future<StreamChainResult>? _developerStreams;
  bool _showDeveloperStreamLinks = false;
  bool _opening = false;

  bool get _isMovie => widget.media.kind == MediaKind.movie;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AppSettingsProvider.of(context);
    final enabled = _isMovie && settings.showDeveloperStreamLinks;
    if (!enabled && _firstSource.hasFocus) _play.requestFocus();
    if (!enabled) _developerStreams = null;
    _showDeveloperStreamLinks = enabled;
  }

  @override
  void dispose() {
    _firstSource.dispose();
    _play.dispose();
    super.dispose();
  }

  void _openAddons() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddonsConfigScreen(
          repository: widget.addonRepository,
          iptvRepository: widget.iptvRepository,
          onAddonsChanged: () {
            if (mounted && _developerStreams != null) {
              setState(() => _developerStreams = null);
            }
          },
        ),
      ),
    );
  }

  Future<void> _showLinks() async {
    final target = _links.currentContext;
    if (_firstSource.context == null && target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 180),
      );
    }
    if (!mounted || _firstSource.context == null) return;
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      _firstSource,
      alignment: 0.3,
    );
  }

  void _reloadLinks() {
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      _play,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    setState(() => _developerStreams = null);
  }

  Future<void> _playPreferred() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final result = await widget.resolveMovieStreams.preferred(widget.media);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final preferred = result.preferredOption;
      if (preferred == null) {
        _showPlaybackUnavailable();
      } else {
        await _openSource(preferred, result, automaticStartup: true);
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

  Future<void> _openSource(
    StreamOption option,
    StreamChainResult result, {
    bool automaticStartup = false,
  }) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    await PlayerScreen.openMedia(
      context,
      title: widget.media.title,
      source: option,
      result: result,
      subtitles: widget.subtitles,
      automaticStartup: automaticStartup,
    );
  }

  Future<void> _openOptions(MediaItem media) async {
    final settings = AppSettingsProvider.of(context);
    final saved = settings.isSaved(media);
    final action = await showModalBottomSheet<_DetailOption>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: StreamingPalette.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.libraryReady)
                TvAction(
                  label: saved
                      ? 'Quitar de Biblioteca'
                      : 'Guardar en Biblioteca',
                  autofocus: true,
                  onPressed: () =>
                      Navigator.of(context).pop(_DetailOption.library),
                  child: ListTile(
                    leading: Icon(
                      saved
                          ? Icons.bookmark_remove_outlined
                          : Icons.bookmark_add_outlined,
                    ),
                    title: Text(
                      saved ? 'Quitar de Biblioteca' : 'Guardar en Biblioteca',
                    ),
                  ),
                ),
              TvAction(
                label: 'Complementos',
                autofocus: !settings.libraryReady,
                onPressed: () =>
                    Navigator.of(context).pop(_DetailOption.addons),
                child: const ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Complementos'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _DetailOption.addons) {
      _openAddons();
      return;
    }
    try {
      await settings.toggleSaved(media);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar la biblioteca.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = isCompactStreamingLayout(size);
    final inset =
        (size.width - 780).clamp(0.0, double.infinity) / 2 +
        (compact ? 20.0 : 36.0);
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: Scaffold(
        backgroundColor: StreamingPalette.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: TvBackButton(autofocus: !_isMovie),
          actions: [
            if (!compact)
              IconButton(
                tooltip: 'Complementos',
                icon: const Icon(Icons.extension_outlined),
                onPressed: _openAddons,
              ),
          ],
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: FutureBuilder<MediaItem>(
            initialData: widget.media,
            future: _details,
            builder: (context, details) {
              final media = details.data ?? widget.media;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: DetailMediaHeader(
                      media: media,
                      actions: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (_isMovie)
                            _DetailAction(
                              label: _opening ? 'Preparando…' : 'Reproducir',
                              icon: Icons.play_arrow_rounded,
                              autofocus: true,
                              focusNode: _play,
                              primary: true,
                              onPressed: _playPreferred,
                            )
                          else
                            const Chip(label: Text('Disponible por episodio')),
                          Tooltip(
                            message: 'Más opciones',
                            excludeFromSemantics: true,
                            child: TvAction(
                              label: 'Más opciones',
                              radius: 24,
                              onPressed: () => _openOptions(media),
                              child: const SizedBox.square(
                                dimension: 48,
                                child: ColoredBox(
                                  color: StreamingPalette.surface,
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_showDeveloperStreamLinks)
                            _DetailAction(
                              label: 'Ver enlaces',
                              icon: Icons.format_list_bulleted_rounded,
                              onPressed: _showLinks,
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DetailMediaMetadata(media: media),
                          const SizedBox(height: 22),
                          const _SectionTitle('Sinopsis'),
                          const SizedBox(height: 9),
                          Text(
                            media.overview.isEmpty
                                ? 'Sin sinopsis disponible.'
                                : media.overview,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: StreamingPalette.muted,
                              height: 1.56,
                            ),
                          ),
                          if (details.hasError) ...[
                            const SizedBox(height: 12),
                            const Text('No se pudo actualizar la ficha.'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_showDeveloperStreamLinks)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 28, inset, 0),
                      sliver: FutureBuilder<StreamChainResult>(
                        future: _developerStreams ??= widget.resolveMovieStreams
                            .developerSources(widget.media),
                        builder: (context, snapshot) => _SourceList(
                          headingKey: _links,
                          snapshot: snapshot,
                          firstSource: _firstSource,
                          onRetry: _reloadLinks,
                          onSelected: _openSource,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 44)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _DetailOption { library, addons }

class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.headingKey,
    required this.snapshot,
    required this.firstSource,
    required this.onRetry,
    required this.onSelected,
  });

  final GlobalKey headingKey;
  final AsyncSnapshot<StreamChainResult> snapshot;
  final FocusNode firstSource;
  final VoidCallback onRetry;
  final void Function(StreamOption, StreamChainResult) onSelected;

  @override
  Widget build(BuildContext context) {
    final result = snapshot.data;
    final options = result?.options ?? const <StreamOption>[];
    final firstPlayable = options.indexWhere((option) => option.isPlayable);
    final loading = snapshot.connectionState != ConnectionState.done;
    final failed = snapshot.hasError || (result?.failures.isNotEmpty ?? false);
    final torrentioInactive = result?.providerNames.isEmpty ?? false;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            key: headingKey,
            padding: const EdgeInsets.only(bottom: 12),
            child: const _SectionTitle('Enlaces de reproducción de Torrentio'),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(semanticsLabel: 'Buscando enlaces'),
          )
        else ...[
          if (options.isEmpty)
            SliverToBoxAdapter(
              child: Text(
                failed
                    ? 'No se pudieron obtener los enlaces de Torrentio.'
                    : torrentioInactive
                    ? 'Activa Torrentio en Complementos para consultar sus enlaces.'
                    : 'No hay enlaces de Torrentio para este título.',
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _DetailAction(
                  label: options.isEmpty ? 'Reintentar' : 'Actualizar enlaces',
                  icon: Icons.refresh_rounded,
                  focusNode: firstPlayable == -1 ? firstSource : null,
                  onPressed: onRetry,
                ),
              ),
            ),
          ),
          if (options.isNotEmpty)
            SliverList.builder(
              itemCount: options.length,
              addAutomaticKeepAlives: false,
              itemBuilder: (context, index) => _SourceTile(
                key: ValueKey((
                  options[index].url,
                  options[index].torrentFileIndex,
                )),
                option: options[index],
                provider:
                    result!.providerNames[options[index].providerId] ??
                    options[index].providerId,
                focusNode: index == firstPlayable ? firstSource : null,
                onPressed: options[index].isPlayable
                    ? () => onSelected(options[index], result)
                    : null,
              ),
            ),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.option,
    required this.provider,
    required this.focusNode,
    required this.onPressed,
    super.key,
  });

  final StreamOption option;
  final String provider;
  final FocusNode? focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final size = option.size;
    final source = option.sourceName;
    final fileIndex = option.torrentFileIndex;
    final seeders = option.seeders;
    final select = onPressed;
    final subtitle = [
      provider,
      if (source != null && source != provider) source,
      if (size != null) '${(size / (1024 * 1024)).toStringAsFixed(1)} MiB',
      if (seeders != null) '$seeders semillas',
      if (option.url.scheme == 'magnet') 'BitTorrent',
      if (fileIndex != null) 'Índice de archivo $fileIndex',
      if (select == null) 'Sin reproducción directa',
    ].join(' · ');
    final theme = Theme.of(context);
    final content = ColoredBox(
      color: StreamingPalette.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              select == null ? Icons.link : Icons.play_circle_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.qualityLabel, style: theme.textTheme.titleMedium),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (select != null) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: select == null
          ? ClipRRect(borderRadius: BorderRadius.circular(12), child: content)
          : TvAction(
              label: '${option.qualityLabel}, $subtitle',
              focusNode: focusNode,
              onPressed: select,
              child: content,
            ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = primary ? StreamingPalette.background : colors.onSurface;
    return TvAction(
      label: label,
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      radius: 26,
      focusOutline: primary ? StreamingPalette.outline : null,
      child: ColoredBox(
        color: primary ? StreamingPalette.accent : StreamingPalette.surface,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: primary ? 28 : 17,
            vertical: 13,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
