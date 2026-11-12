import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'streaming_theme.dart';
import 'tv_action.dart';

enum MobileDestination { home, search, library, profile }

final class MobileCatalogNavigation extends StatefulWidget {
  const MobileCatalogNavigation({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final MobileDestination selected;
  final ValueChanged<MobileDestination> onSelected;

  @override
  State<MobileCatalogNavigation> createState() =>
      _MobileCatalogNavigationState();
}

class _MobileCatalogNavigationState extends State<MobileCatalogNavigation>
    with SingleTickerProviderStateMixin {
  static const _curve = Curves.easeInOutCubic;
  static const _gap = 4.0;

  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  Map<MobileDestination, double> _from = const {};
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _animation.value = 1;
  }

  @override
  void didUpdateWidget(covariant MobileCatalogNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    if (_reduceMotion) {
      _animation.value = 1;
      return;
    }
    final progress = _curve.transform(_animation.value);
    _from = {
      for (final item in MobileDestination.values)
        item: _weight(item, oldWidget.selected, progress),
    };
    _animation.forward(from: 0);
  }

  double _weight(
    MobileDestination item,
    MobileDestination selected,
    double progress,
  ) => lerpDouble(_from[item] ?? 0, item == selected ? 1 : 0, progress)!;

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      StreamingPalette.glass,
                      StreamingPalette.glassDark,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x3DFFFFFF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final count = MobileDestination.values.length;
                      final available = math.max(
                        0.0,
                        constraints.maxWidth - _gap * (count - 1),
                      );
                      final equalWidth = available / count;
                      final compact = (available * .18)
                          .clamp(
                            math.min(48.0, equalWidth),
                            math.min(64.0, equalWidth),
                          )
                          .toDouble();
                      final expansion = available - compact * count;
                      return AnimatedBuilder(
                        animation: _animation,
                        builder: (context, _) {
                          final progress = _curve.transform(_animation.value);
                          return Row(
                            spacing: _gap,
                            children: [
                              for (final item in MobileDestination.values)
                                _destination(
                                  item,
                                  _weight(item, widget.selected, progress),
                                  compact,
                                  expansion,
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _destination(
    MobileDestination item,
    double weight,
    double compact,
    double expansion,
  ) {
    final (label, icon) = switch (item) {
      MobileDestination.home => ('Inicio', Icons.home_rounded),
      MobileDestination.search => ('Buscar', Icons.search_rounded),
      MobileDestination.library => ('Biblioteca', Icons.bookmarks_outlined),
      MobileDestination.profile => ('Perfil', Icons.person_outline_rounded),
    };
    final width = compact + expansion * weight;
    final labelProgress = ((weight - .24) / .76).clamp(0.0, 1.0);
    final iconColor = Color.lerp(
      StreamingPalette.muted,
      StreamingPalette.accent,
      weight,
    );
    return SizedBox(
      key: ValueKey(item),
      width: width,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: TvAction(
          label: label,
          selected: item == widget.selected,
          focusOutline: StreamingPalette.accent,
          onPressed: () => widget.onSelected(item),
          radius: 22,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ColoredBox(
              color: StreamingPalette.raised.withValues(alpha: weight),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: lerpDouble(21, 24, weight),
                      color: iconColor,
                    ),
                    if (labelProgress > 0 && width >= 62)
                      Flexible(
                        child: ClipRect(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: labelProgress,
                            child: Opacity(
                              opacity: labelProgress,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 7,
                                  end: 5,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StreamingPalette.active,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
