// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/entities/media_item.dart';
import 'catalog_image.dart';
import 'streaming_theme.dart';
import 'tv_action.dart';

bool isCompactStreamingLayout(Size size) =>
    size.width < 650 || (size.width < 950 && size.height < 500);

final class CatalogHero extends StatelessWidget {
  const CatalogHero({
    required this.media,
    required this.inset,
    required this.compact,
    required this.playFocus,
    required this.detailsFocus,
    required this.isOpening,
    required this.onPlay,
    required this.onDetails,
    super.key,
  });

  final MediaItem media;
  final double inset;
  final bool compact;
  final FocusNode playFocus;
  final FocusNode detailsFocus;
  final bool isOpening;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final type = switch (media.type) {
      MediaType.movie => 'Película',
      MediaType.series => 'Serie',
      MediaType.anime => 'Anime',
      MediaType.cartoon => 'Dibujos',
    };
    final year = media.releaseYear;
    final rating = media.rating;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            left: compact ? 0 : constraints.maxWidth * .17,
            child: CatalogImage(
              uri: media.backdropImage ?? media.posterImage,
              panorama: media.backdropImage != null,
              alignment: compact
                  ? const Alignment(.48, -.12)
                  : Alignment.center,
            ),
          ),
          if (!compact)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      StreamingPalette.background,
                      Color(0xE80B0D12),
                      Color(0x290B0D12),
                      Color(0x000B0D12),
                    ],
                    stops: [0, .27, .66, 1],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: compact
                      ? const [
                          Color(0x100B0D12),
                          Color(0x5E0B0D12),
                          Color(0xF50B0D12),
                          StreamingPalette.background,
                        ]
                      : const [
                          Color(0x260B0D12),
                          Color(0x000B0D12),
                          Color(0x750B0D12),
                          StreamingPalette.background,
                        ],
                  stops: compact
                      ? const [0, .28, .73, 1]
                      : const [0, .5, .79, 1],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            constraints: BoxConstraints(
              minHeight: compact
                  ? 374
                  : (constraints.maxWidth * .39).clamp(400.0, 570.0),
            ),
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.fromLTRB(
              inset,
              compact ? 127 : 112,
              inset,
              compact ? 26 : 42,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 555),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Badge(type, accent: true),
                      if (year != null) _Badge('$year'),
                      if (rating != null)
                        _Badge('★ ${rating.toStringAsFixed(1)}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 43 : 72,
                      height: 1.02,
                      letterSpacing: compact ? -1.6 : -3,
                    ),
                  ),
                  if (media.overview.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      media.overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: StreamingPalette.active,
                        height: 1.48,
                        fontSize: compact ? 14 : 17,
                      ),
                    ),
                  ],
                  const SizedBox(height: 21),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _HeroAction(
                        label: isOpening ? 'Preparando…' : 'Reproducir',
                        semantics: 'Reproducir ${media.title}',
                        icon: Icons.play_arrow_rounded,
                        focusNode: playFocus,
                        onPressed: onPlay,
                        primary: true,
                      ),
                      _HeroAction(
                        label: 'Detalles',
                        semantics: 'Ver detalles de ${media.title}',
                        icon: Icons.info_outline,
                        focusNode: detailsFocus,
                        onPressed: onDetails,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.accent = false, this.poster = false});

  final String label;
  final bool accent;
  final bool poster;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: poster
          ? (accent ? StreamingPalette.accent : const Color(0xE60B0D12))
          : (accent ? StreamingPalette.glassDark : StreamingPalette.glass),
      borderRadius: BorderRadius.circular(5),
      border: poster
          ? null
          : Border.all(
              color: accent
                  ? StreamingPalette.outline
                  : const Color(0x55FFFFFF),
            ),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: poster ? 6 : 8, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          color: accent
              ? (poster ? StreamingPalette.background : StreamingPalette.accent)
              : Colors.white,
          fontSize: poster ? 9 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
      ),
    ),
  );
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.label,
    required this.semantics,
    required this.icon,
    required this.focusNode,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final String semantics;
  final IconData icon;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? StreamingPalette.background : Colors.white;
    return TvAction(
      label: semantics,
      focusNode: focusNode,
      radius: 8,
      focusOutline: primary ? StreamingPalette.outline : null,
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary ? StreamingPalette.accent : StreamingPalette.glass,
          border: primary ? null : Border.all(color: const Color(0x557A869A)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class CatalogPoster extends StatelessWidget {
  const CatalogPoster({
    required this.media,
    required this.width,
    required this.onPressed,
    this.focusNode,
    this.showYear = false,
    super.key,
  });

  final MediaItem media;
  final double width;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool showYear;

  static double heightFor(
    BuildContext context,
    double width, {
    required bool showYear,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    return (width * 1.5 +
            23 +
            scaler.scale(13) * 1.35 +
            (showYear ? 3 + scaler.scale(12) * 1.35 : 0))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final quality = media.qualityLabel;
    final year = media.releaseYear;
    return TvAction(
      label: media.title,
      onPressed: onPressed,
      focusNode: focusNode,
      highlightOnHover: true,
      radius: 11,
      child: SizedBox(
        width: width,
        child: ColoredBox(
          color: StreamingPalette.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CatalogImage(uri: media.posterImage),
                    if (media.isPremiere && !showYear)
                      const Positioned(
                        top: 9,
                        left: 9,
                        child: _Badge('ESTRENO', accent: true, poster: true),
                      ),
                    if (quality != null && !showYear)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _Badge(quality, poster: true),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: StreamingPalette.active,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (showYear && year != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '$year',
                        style: const TextStyle(
                          color: StreamingPalette.muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
