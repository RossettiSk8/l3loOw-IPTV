// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/entities/media_item.dart';
import 'catalog_image.dart';
import 'home_catalog.dart';
import 'streaming_theme.dart';

final class DetailMediaHeader extends StatelessWidget {
  const DetailMediaHeader({
    required this.media,
    required this.actions,
    super.key,
  });

  final MediaItem media;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = isCompactStreamingLayout(MediaQuery.sizeOf(context));
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: CatalogImage(
            uri: media.backdropImage ?? media.posterImage,
            panorama: media.backdropImage != null,
            alignment: const Alignment(.35, -.35),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .34, .74, 1],
                colors: [
                  Color(0x7D0B0D12),
                  Color(0x100B0D12),
                  Color(0xDF0B0D12),
                  StreamingPalette.background,
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: (width * .91).clamp(345.0, 510.0),
          ),
          padding: EdgeInsets.fromLTRB(20, compact ? 170 : 230, 20, 18),
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    media.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 42 : 62,
                      height: 1.03,
                      letterSpacing: compact ? -1.5 : -2,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (media.genres.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    media.genres.join(' · '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: StreamingPalette.active,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 21),
                actions,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class DetailMediaMetadata extends StatelessWidget {
  const DetailMediaMetadata({required this.media, super.key});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final year = media.releaseYear;
    final runtime = media.runtimeMinutes;
    final imdbRating = media.imdbRating;
    final rating = imdbRating ?? media.rating;
    final ratingSource = imdbRating == null
        ? (media.ratingSource ?? '★')
        : 'IMDb';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 7,
          alignment: WrapAlignment.center,
          children: [
            if (year != null) _InfoTag('$year'),
            if (runtime != null) _InfoTag(_duration(runtime)),
            _InfoTag(media.ageRating ?? 'Sin clasificar'),
            if (rating != null)
              _InfoTag(
                '$ratingSource ${rating.toStringAsFixed(1)}',
                rating: true,
              ),
          ],
        ),
        if (media.directors.isNotEmpty || media.writers.isNotEmpty) ...[
          const SizedBox(height: 24),
          if (media.directors.isNotEmpty)
            _Credit(label: 'Dirección', names: media.directors),
          if (media.writers.isNotEmpty)
            _Credit(label: 'Guion', names: media.writers),
        ],
      ],
    );
  }

  String _duration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$minutes min';
    return remainder == 0 ? '$hours h' : '$hours h $remainder min';
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag(this.label, {this.rating = false});

  final String label;
  final bool rating;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: rating ? StreamingPalette.raised : StreamingPalette.surface,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(
        color: rating ? StreamingPalette.outline : StreamingPalette.divider,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          color: rating ? StreamingPalette.accent : StreamingPalette.active,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Credit extends StatelessWidget {
  const _Credit({required this.label, required this.names});

  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: names.join(', ')),
        ],
      ),
      style: const TextStyle(
        color: StreamingPalette.muted,
        fontSize: 14,
        height: 1.4,
      ),
    ),
  );
}
