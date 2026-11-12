// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/repositories/manage_app_updates.dart';
import 'ota_update_dialog.dart';
import 'tv_action.dart';

final class VersionUpdatesPanel extends StatefulWidget {
  const VersionUpdatesPanel({required this.updates, super.key});

  final ManageAppUpdates? updates;

  @override
  State<VersionUpdatesPanel> createState() => _VersionUpdatesPanelState();
}

class _VersionUpdatesPanelState extends State<VersionUpdatesPanel> {
  Future<InstalledAppVersion>? _version;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _version = widget.updates?.installedVersion();
  }

  @override
  void didUpdateWidget(VersionUpdatesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      _version = widget.updates?.installedVersion();
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    final updates = widget.updates;
    if (updates == null || !updates.canCheckForUpdates) {
      setState(
        () => _message = 'El canal de actualizaciones no está disponible.',
      );
      return;
    }
    setState(() {
      _checking = true;
      _message = 'Buscando actualizaciones…';
    });
    try {
      final release = await updates.check();
      if (!mounted) return;
      setState(() {
        _message = release == null ? 'l3loOw está actualizado.' : null;
      });
      if (release != null) {
        await OtaUpdateDialog.show(context, updates, release);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo buscar actualizaciones. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acerca de l3loOw', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        FutureBuilder<InstalledAppVersion>(
          future: _version,
          builder: (context, snapshot) {
            final installed = snapshot.data;
            final label = switch (installed) {
              (version: final version, build: final build?) =>
                'Versión $version · Compilación $build',
              (version: final version, build: null) =>
                'Versión $version · Compilación no disponible',
              null when snapshot.connectionState == ConnectionState.waiting =>
                'Leyendo la versión instalada…',
              null => 'Versión y compilación no disponibles.',
            };
            return Text(
              label,
              style: TextStyle(color: colors.onSurfaceVariant),
            );
          },
        ),
        const SizedBox(height: 12),
        TvAction(
          label: 'Buscar actualizaciones',
          onPressed: _check,
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('Buscar actualizaciones'),
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(message)),
        ],
        if (_checking && message != null) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
