import '../../domain/contracts/addon_repository.dart';
import '../../domain/contracts/stream_provider_contract.dart';
import '../../domain/contracts/stream_resolver.dart';
import '../../domain/entities/stream_chain_result.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/entities/stream_request.dart';
import '../../domain/repositories/addon_priority.dart';
import '../../domain/repositories/stream_startup_policy.dart';

export '../../domain/entities/stream_chain_result.dart';

enum StreamChainMode { collectAll, firstAvailable }

final class StreamManager implements StreamResolver {
  StreamManager({
    required AddonRepository addons,
    this.providerTimeout = const Duration(seconds: 8),
  }) : _addons = addons;

  final AddonRepository _addons;
  final Duration providerTimeout;
  final _providers = <String, StreamProviderContract>{};

  /// Asocia o reemplaza el adaptador de un complemento del repositorio.
  void register(String addonId, StreamProviderContract provider) {
    _providers[addonId] = provider;
  }

  @override
  Future<StreamChainResult> resolvePreferred(StreamRequest request) =>
      resolve(request, mode: StreamChainMode.firstAvailable);

  @override
  Future<StreamChainResult> resolve(
    StreamRequest request, {
    StreamChainMode mode = StreamChainMode.collectAll,
    Set<String>? addonIds,
  }) async {
    final providers = Map.of(_providers);
    final selectedIds = addonIds?.toSet();
    final addons = [...await _addons.list()]..sort(compareAddonPriority);
    final options = <(Uri, int?), StreamOption>{};
    final startup = <Uri, StreamOption>{};
    final zeroSeeders = <Uri, StreamOption>{};
    final failures = <StreamProviderFailure>[];
    final providerNames = <String, String>{};

    for (final addon in addons) {
      final provider = providers[addon.id];
      if (!addon.isEnabled ||
          provider == null ||
          (selectedIds != null && !selectedIds.contains(addon.id))) {
        continue;
      }

      providerNames[addon.id] = addon.name;
      try {
        final streams = await provider
            .getStreams(request, addon)
            .timeout(providerTimeout);
        for (final stream in streams) {
          options.putIfAbsent((
            stream.url,
            stream.torrentFileIndex,
          ), () => stream);
        }
        if (mode == StreamChainMode.firstAvailable) {
          final playable = streams.where((stream) => stream.isPlayable);
          for (final stream in rankStartupSources(playable, request)) {
            final candidates = stream.seeders == 0 ? zeroSeeders : startup;
            candidates.putIfAbsent(stream.url, () => stream);
          }
          // Un HTTP con cero semillas aún puede estar cacheado por el proveedor.
          if (startup.isNotEmpty) break;
        }
      } on Exception catch (error) {
        failures.add(StreamProviderFailure(addon.id, error));
      }
    }
    return StreamChainResult(
      options: options.values,
      failures: failures,
      providerNames: providerNames,
      startupOptions: mode == StreamChainMode.firstAvailable
          ? [
              ...startup.values,
              ...zeroSeeders.values.where(
                (stream) => !startup.containsKey(stream.url),
              ),
            ]
          : null,
    );
  }
}
