// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/contracts/addon_repository.dart';
import '../../domain/contracts/iptv_repository.dart';
import '../../domain/entities/addon_entity.dart';
import '../widgets/app_settings_provider.dart';
import '../widgets/iptv_settings_panel.dart';
import '../widgets/tv_action.dart';
import '../widgets/version_updates_panel.dart';

final class AddonsConfigScreen extends StatefulWidget {
  const AddonsConfigScreen({
    required this.repository,
    required this.iptvRepository,
    this.onAddonsChanged,
    super.key,
  });

  final AddonRepository repository;
  final IptvRepository iptvRepository;
  final VoidCallback? onAddonsChanged;

  @override
  State<AddonsConfigScreen> createState() => _AddonsConfigScreenState();
}

class _AddonsConfigScreenState extends State<AddonsConfigScreen> {
  List<AddonEntity>? _addons;
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loadFailed = false);
    try {
      final addons = await widget.repository.list();
      if (mounted) setState(() => _addons = addons);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _change(Future<void> Function() save) async {
    if (_busy) return;
    final onAddonsChanged = widget.onAddonsChanged;
    setState(() => _busy = true);
    try {
      await save();
      onAddonsChanged?.call();
      final addons = await widget.repository.list();
      if (mounted) setState(() => _addons = addons);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo actualizar la configuración.'),
            action: SnackBarAction(label: 'Recargar', onPressed: _refresh),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDeveloperLinks(AppSettings settings, bool enabled) async {
    try {
      await settings.setShowDeveloperStreamLinks(enabled);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el modo desarrollador.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final addons = _addons;
    final settings = AppSettingsProvider.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: Navigator.canPop(context)
          ? AppBar(
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              leading: const TvBackButton(),
            )
          : null,
      body: SafeArea(
        child: FocusTraversalGroup(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset =
                  (constraints.maxWidth - 760).clamp(40.0, double.infinity) / 2;
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 16, inset, 36),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Text(
                              'Ajustes',
                              style: theme.textTheme.headlineLarge,
                            ),
                          ),
                        ),
                        _SettingsSection(
                          title: 'Complementos VOD',
                          icon: Icons.extension_outlined,
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Los complementos activos se consultan de arriba hacia abajo.',
                                  ),
                                  const SizedBox(height: 12),
                                  if (_busy) const LinearProgressIndicator(),
                                  if (_loadFailed)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FilledButton(
                                        autofocus: addons == null,
                                        onPressed: _refresh,
                                        child: const Text(
                                          'Reintentar cargar complementos',
                                        ),
                                      ),
                                    )
                                  else if (addons == null)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (addons.isEmpty)
                                    const Text(
                                      'No hay complementos registrados.',
                                    ),
                                ],
                              ),
                            ),
                            if (!_loadFailed && addons != null)
                              SliverList.builder(
                                itemCount: addons.length,
                                addAutomaticKeepAlives: false,
                                itemBuilder: (context, index) =>
                                    _buildAddon(addons, index),
                              ),
                            SliverToBoxAdapter(
                              child: Card(
                                child: SwitchListTile(
                                  title: const Text('Modo desarrollador'),
                                  subtitle: const Text(
                                    'Mostrar enlaces técnicos de Torrentio',
                                  ),
                                  value: settings.showDeveloperStreamLinks,
                                  onChanged: settings.isReady
                                      ? (enabled) => _setDeveloperLinks(
                                          settings,
                                          enabled,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        _SettingsSection(
                          title: 'IPTV / Canales en vivo',
                          icon: Icons.live_tv_outlined,
                          slivers: [
                            IptvSettingsPanel(
                              repository: widget.iptvRepository,
                            ),
                          ],
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        _SettingsSection(
                          title: 'Versión y actualizaciones',
                          icon: Icons.system_update_outlined,
                          slivers: [
                            SliverToBoxAdapter(
                              child: VersionUpdatesPanel(
                                updates: AppSettingsProvider.updatesOf(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAddon(List<AddonEntity> addons, int index) {
    final addon = addons[index];
    final repository = widget.repository;
    return _AddonCard(
      key: ValueKey(addon.id),
      addon: addon,
      autofocus: index == 0,
      onEnabled: (enabled) =>
          _change(() => repository.setEnabled(addon.id, enabled)),
      onUp: index == 0
          ? null
          : () => _change(() => repository.move(addon.id, AddonMove.up)),
      onDown: index == addons.length - 1
          ? null
          : () => _change(() => repository.move(addon.id, AddonMove.down)),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.slivers,
  });

  final String title;
  final IconData icon;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ...slivers,
          ],
        ),
      ),
    );
  }
}

class _AddonCard extends StatelessWidget {
  const _AddonCard({
    required this.addon,
    required this.autofocus,
    required this.onEnabled,
    this.onUp,
    this.onDown,
    super.key,
  });

  final AddonEntity addon;
  final bool autofocus;
  final ValueChanged<bool> onEnabled;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            autofocus: autofocus,
            title: Text(addon.name),
            subtitle: Text(addon.isEnabled ? 'Activo' : 'Desactivado'),
            value: addon.isEnabled,
            onChanged: onEnabled,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Prioridad ${addon.priority}',
                  style: theme.textTheme.bodyMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Subir prioridad de ${addon.name}',
                      onPressed: onUp,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Bajar prioridad de ${addon.name}',
                      onPressed: onDown,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
