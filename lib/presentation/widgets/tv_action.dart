// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

final class TvBackButton extends StatelessWidget {
  const TvBackButton({this.autofocus = false, super.key});

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Tooltip(
        message: 'Volver',
        excludeFromSemantics: true,
        child: TvAction(
          label: 'Volver',
          autofocus: autofocus,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const SizedBox.expand(child: BackButtonIcon()),
        ),
      ),
    );
  }
}

final class TvAction extends StatefulWidget {
  const TvAction({
    required this.label,
    required this.onPressed,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.radius = 12,
    this.selected,
    this.highlightOnHover = false,
    this.focusOutline,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;
  final double radius;
  final bool? selected;
  final bool highlightOnHover;
  final Color? focusOutline;

  @override
  State<TvAction> createState() => _TvActionState();
}

class _TvActionState extends State<TvAction> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    final focusColor =
        widget.focusOutline ?? Theme.of(context).colorScheme.primary;
    final highlighted = _focused || _hovered;
    return Semantics(
      label: widget.label,
      button: true,
      focusable: true,
      focused: _focused,
      selected: widget.selected,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: widget.highlightOnHover && highlighted ? 1.035 : 1,
        duration: const Duration(milliseconds: 140),
        child: Stack(
          children: [
            ClipRRect(borderRadius: radius, child: widget.child),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  autofocus: widget.autofocus,
                  focusNode: widget.focusNode,
                  borderRadius: radius,
                  excludeFromSemantics: true,
                  focusColor: Colors.transparent,
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  onHover: widget.highlightOnHover
                      ? (hovered) => setState(() => _hovered = hovered)
                      : null,
                  onTap: widget.onPressed,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: highlighted ? focusColor : Colors.transparent,
                        width: _focused ? 3 : 2,
                      ),
                      boxShadow: widget.highlightOnHover && highlighted
                          ? [
                              BoxShadow(
                                color: focusColor.withAlpha(58),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
