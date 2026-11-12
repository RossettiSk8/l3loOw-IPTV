// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/contracts/iptv_repository.dart';
import '../../domain/entities/iptv_playlist.dart';
import 'app_settings_provider.dart';

final class IptvSettingsPanel extends StatefulWidget {
  const IptvSettingsPanel({required this.repository, super.key});

  final IptvRepository repository;

  @override
  State<IptvSettingsPanel> createState() => _IptvSettingsPanelState();
}

class _IptvSettingsPanelState extends State<IptvSettingsPanel> {
  late Future<List<IptvPlaylist>> _playlists = widget.repository.list();
  final _addFocus = FocusNode(debugLabel: 'Agregar lista IPTV');
  bool _busy = false;

  @override
  void dispose() {
    _addFocus.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _playlists = widget.repository.list();
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setEnabled(AppSettings settings, bool enabled) async {
    try {
      await settings.setIptvEnabled(enabled);
    } catch (_) {
      if (mounted) _message('No se pudo guardar el estado de IPTV.');
    }
  }

  Future<void> _change(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) return;
      _reload();
      _message(message);
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('No se pudo actualizar la biblioteca IPTV.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final address = await showDialog<String>(
      context: context,
      builder: (_) => const _PlaylistUrlDialog(),
    );
    if (!mounted || address == null) return;
    await _change(() async {
      await widget.repository.addPlaylist(address);
      return 'Lista agregada.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsProvider.of(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Card(
            child: SwitchListTile(
              title: const Text('Activar IPTV'),
              subtitle: const Text('Mostrar el acceso a TV en vivo en Inicio'),
              value: settings.iptvEnabled,
              onChanged: settings.isReady
                  ? (enabled) => _setEnabled(settings, enabled)
                  : null,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        FutureBuilder<List<IptvPlaylist>>(
          future: _playlists,
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? const <IptvPlaylist>[];
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          focusNode: _addFocus,
                          onPressed: _add,
                          icon: const Icon(Icons.add_link),
                          label: const Text('Agregar lista'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              playlists.any((item) => item.channels.isNotEmpty)
                              ? () => _change(() async {
                                  final count = await widget.repository
                                      .purgeBrokenLinks();
                                  return count == 0
                                      ? 'No se confirmaron enlaces rotos.'
                                      : 'Entradas eliminadas: $count.';
                                })
                              : null,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('Purgar enlaces rotos'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_busy ||
                    snapshot.connectionState == ConnectionState.waiting)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Actualizando listas IPTV',
                    ),
                  ),
                if (snapshot.hasError)
                  SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _reload,
                        child: const Text('Reintentar cargar listas'),
                      ),
                    ),
                  )
                else if (snapshot.connectionState == ConnectionState.done &&
                    playlists.isEmpty)
                  const SliverToBoxAdapter(
                    child: Text(
                      'Agrega una URL M3U o M3U8 para cargar canales.',
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: playlists.length,
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) =>
                        _playlistCard(playlists[index]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _playlistCard(IptvPlaylist playlist) => Card(
    key: ValueKey(playlist.url),
    child: ListTile(
      leading: const Icon(Icons.playlist_play),
      title: Text(playlist.url.host, overflow: TextOverflow.ellipsis),
      subtitle: Text('Canales: ${playlist.channels.length}'),
      trailing: IconButton(
        tooltip: 'Eliminar lista de ${playlist.url.host}',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _change(() async {
          await widget.repository.removePlaylist(playlist.url);
          if (mounted) _addFocus.requestFocus();
          return 'Lista eliminada.';
        }),
      ),
    ),
  );
}

class _PlaylistUrlDialog extends StatefulWidget {
  const _PlaylistUrlDialog();

  @override
  State<_PlaylistUrlDialog> createState() => _PlaylistUrlDialogState();
}

class _PlaylistUrlDialogState extends State<_PlaylistUrlDialog> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _address.text.trim();
    if (address.isNotEmpty) Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agregar lista IPTV'),
    content: TextField(
      autofocus: true,
      controller: _address,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: 'URL de la lista',
        hintText: 'https://ejemplo.com/canales.m3u',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _address,
        builder: (context, value, child) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : _submit,
          child: child,
        ),
        child: const Text('Agregar'),
      ),
    ],
  );
}
