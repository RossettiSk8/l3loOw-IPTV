// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/media_item.dart';
import 'catalog_image.dart';
import 'streaming_theme.dart';
import 'tv_action.dart';

final class MobileCatalogHero extends StatefulWidget {
  const MobileCatalogHero({
    required this.items,
    required this.detailsFocus,
    required this.onDetails,
    super.key,
  });

  final List<MediaItem> items;
  final FocusNode detailsFocus;
  final ValueChanged<MediaItem> onDetails;

  @override
  State<MobileCatalogHero> createState() => _MobileCatalogHeroState();
}

class _MobileCatalogHeroState extends State<MobileCatalogHero> {
  final _pages = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant MobileCatalogHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.items.length) _index = 0;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (_pages.hasClients && index >= 0 && index < widget.items.length) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.items[_index];
    final year = media.releaseYear;
    final metadata = [...media.genres.take(2), if (year != null) '$year'];
    final height = (MediaQuery.sizeOf(context).width * .94).clamp(324.0, 408.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return CatalogImage(
                uri: item.backdropImage ?? item.posterImage,
                panorama: item.backdropImage != null,
                alignment: const Alignment(.35, -.35),
              );
            },
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x080B0D12),
                    Color(0x180B0D12),
                    Color(0xCC0B0D12),
                    StreamingPalette.background,
                  ],
                  stops: [0, .30, .70, 1],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IgnorePointer(
                    child: Column(
                      children: [
                        Text(
                          media.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 37,
                            height: 1.02,
                            letterSpacing: -1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (metadata.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            metadata.join(' · '),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: StreamingPalette.active,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _goTo(_index - 1);
                      } else if (key == LogicalKeyboardKey.arrowRight) {
                        _goTo(_index + 1);
                      } else {
                        return KeyEventResult.ignored;
                      }
                      return KeyEventResult.handled;
                    },
                    child: TvAction(
                      label: 'Ver detalles de ${media.title}',
                      focusNode: widget.detailsFocus,
                      focusOutline: StreamingPalette.outline,
                      radius: 24,
                      onPressed: () => widget.onDetails(media),
                      child: const ColoredBox(
                        color: StreamingPalette.accent,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 23,
                            vertical: 13,
                          ),
                          child: Text(
                            'Ver detalles',
                            style: TextStyle(
                              color: StreamingPalette.background,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 17),
                  if (widget.items.length > 1)
                    Semantics(
                      label:
                          'Destacado ${_index + 1} de ${widget.items.length}',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = 0;
                            index < widget.items.length;
                            index++
                          )
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: index == _index ? 8 : 6,
                              height: index == _index ? 8 : 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index == _index
                                    ? Colors.white
                                    : const Color(0x6FFFFFFF),
                              ),
                            ),
                        ],
                      ),
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
