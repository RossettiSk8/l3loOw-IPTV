import 'dart:async';

// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/ota_update.dart';
import '../../domain/repositories/manage_app_updates.dart';
import 'streaming_theme.dart';
import 'tv_action.dart';

final class OtaStartupCheck extends StatefulWidget {
  const OtaStartupCheck({
    required this.updates,
    required this.child,
    super.key,
  });

  final ManageAppUpdates? updates;
  final Widget child;

  @override
  State<OtaStartupCheck> createState() => _OtaStartupCheckState();
}

class _OtaStartupCheckState extends State<OtaStartupCheck> {
  @override
  void initState() {
    super.initState();
    final updates = widget.updates;
    if (updates != null && updates.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check(updates));
      });
    }
  }

  Future<void> _check(ManageAppUpdates updates) async {
    try {
      final release = await updates.check();
      if (mounted && release != null) {
        await OtaUpdateDialog.show(context, updates, release);
      }
    } catch (_) {
      // El catálogo sigue disponible si falla la consulta de inicio.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class OtaUpdateDialog extends StatefulWidget {
  const OtaUpdateDialog._({required this.updates, required this.release});

  final ManageAppUpdates updates;
  final OtaUpdate release;

  static final _activeDialog = Expando<Future<void>>();

  static Future<void> show(
    BuildContext context,
    ManageAppUpdates updates,
    OtaUpdate release,
  ) {
    final navigator = Navigator.of(context, rootNavigator: true);
    return _activeDialog[navigator] ??= showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xC4030509),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) =>
          OtaUpdateDialog._(updates: updates, release: release),
    ).whenComplete(() => _activeDialog[navigator] = null);
  }

  @override
  State<OtaUpdateDialog> createState() => _OtaUpdateDialogState();
}

class _OtaUpdateDialogState extends State<OtaUpdateDialog> {
  static const _accent = Color(0xFFB42336);
  static const _background = Color(0xF50B0D12);
  final _notesController = ScrollController();
  StreamSubscription<OtaProgress>? _subscription;
  OtaProgress? _progress;
  bool _notesFocused = false;
  bool _busy = false;
  bool _failed = false;
  bool _showWebOsInstructions = false;

  void _activate() {
    if (_busy) return;
    if (widget.release.platform == OtaPlatform.webos) {
      setState(() => _showWebOsInstructions = !_showWebOsInstructions);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _progress = null;
    });
    _subscription = widget.updates
        .install(widget.release)
        .listen(
          (progress) => setState(() => _progress = progress),
          onError: (Object error, StackTrace stack) =>
              setState(() => _failed = true),
          onDone: () => setState(() {
            _busy = false;
            _subscription = null;
          }),
        );
  }

  KeyEventResult _scrollNotes(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_notesController.hasClients) {
      return KeyEventResult.ignored;
    }
    final offset = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 70.0,
      LogicalKeyboardKey.arrowUp => -70.0,
      _ => 0.0,
    };
    final position = _notesController.position;
    final destination = (position.pixels + offset).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (destination == position.pixels) return KeyEventResult.ignored;
    _notesController.jumpTo(destination);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final progress = _progress;
    final canDismiss = !release.mandatory && !_busy;
    final theme = Theme.of(context);
    final date = release.publishedAt;
    final version = 'Versión ${release.version}';
    final metadata = date == null
        ? version
        : '$version · ${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/${date.year}';
    final status = _failed
        ? 'No se pudo preparar la actualización. Inténtalo de nuevo.'
        : switch (progress?.stage) {
            OtaStage.downloading =>
              'Descargando · ${((progress!.fraction ?? 0) * 100).round()} %',
            OtaStage.verifying => 'Verificando SHA-256…',
            OtaStage.installerOpened => 'Confirma la instalación en Android.',
            OtaStage.permissionRequired =>
              'Autoriza la instalación en Android y vuelve a intentarlo.',
            null => _busy ? 'Preparando la descarga…' : null,
          };
    return PopScope(
      canPop: canDismiss,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        constraints: const BoxConstraints(maxWidth: 620),
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 20,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: StreamingPalette.divider),
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B1822),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    child: Text(
                      release.mandatory
                          ? 'VERSIÓN NO COMPATIBLE'
                          : 'ACTUALIZACIÓN DISPONIBLE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFFFFA5AF),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Semantics(
                header: true,
                child: Text(
                  'Nueva versión disponible',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                metadata,
                style: const TextStyle(color: StreamingPalette.muted),
              ),
              const SizedBox(height: 22),
              _buildNotes(release.releaseNotes),
              if (_showWebOsInstructions) ...[
                const SizedBox(height: 16),
                const Text(
                  'Busca l3loOw en LG Apps. En equipos de desarrollo, '
                  'el administrador puede instalar el IPK con la CLI de LG.',
                ),
                const SizedBox(height: 6),
                Text(
                  release.url.toString(),
                  style: const TextStyle(color: StreamingPalette.muted),
                ),
              ],
              const SizedBox(height: 22),
              if (_busy)
                LinearProgressIndicator(
                  value: progress?.fraction,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFFF7888),
                  backgroundColor: StreamingPalette.raised,
                  semanticsLabel: 'Progreso de actualización',
                )
              else
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (canDismiss)
                      _UpdateAction(
                        label: 'Más tarde',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    _UpdateAction(
                      label: _showWebOsInstructions
                          ? 'Ocultar instrucciones'
                          : 'Actualizar ahora',
                      onPressed: _activate,
                      primary: true,
                    ),
                  ],
                ),
              if (status != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: progress?.stage != OtaStage.downloading,
                  child: Text(status),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotes(List<String> notes) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Novedades y mejoras',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (notes.isEmpty)
          const Text('Esta versión no incluye notas de publicación.')
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * 0.25).clamp(
                72.0,
                180.0,
              ),
            ),
            child: Scrollbar(
              controller: _notesController,
              thumbVisibility: _notesFocused,
              child: SingleChildScrollView(
                controller: _notesController,
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final note in notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•'),
                            const SizedBox(width: 8),
                            Expanded(child: Text(note)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    return Focus(
      canRequestFocus: notes.isNotEmpty,
      onFocusChange: (focused) => setState(() => _notesFocused = focused),
      onKeyEvent: _scrollNotes,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StreamingPalette.glassDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _notesFocused
                ? StreamingPalette.accent
                : StreamingPalette.divider,
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(14), child: body),
      ),
    );
  }
}

class _UpdateAction extends StatelessWidget {
  const _UpdateAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => TvAction(
    label: label,
    autofocus: primary,
    onPressed: onPressed,
    radius: 14,
    child: ColoredBox(
      color: primary ? _OtaUpdateDialogState._accent : StreamingPalette.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
