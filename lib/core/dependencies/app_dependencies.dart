import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../data/adapters/demo_media_repository.dart';
import '../../data/adapters/demo_stream_provider.dart';
import '../../data/adapters/m3u_playlist_loader.dart';
import '../../data/adapters/ota_updater_adapter.dart';
import '../../data/adapters/tmdb_repository.dart';
import '../../data/adapters/torrentio_adapter.dart';
import '../../data/adapters/webos_video_player.dart';
import '../../data/network/json_api.dart';
import '../../data/repositories/http_subtitle_repository.dart';
import '../../data/repositories/local_addon_repository.dart';
import '../../data/repositories/local_iptv_repository.dart';
import '../../data/repositories/local_media_library_repository.dart';
import '../../data/repositories/local_playback_preferences_repository.dart';
import '../../data/streams/stream_manager.dart';
import '../../domain/contracts/addon_repository.dart';
import '../../domain/contracts/iptv_repository.dart';
import '../../domain/contracts/media_repository.dart';
import '../../domain/contracts/media_library_repository.dart';
import '../../domain/contracts/playback_preferences_repository.dart';
import '../../domain/contracts/stream_provider_contract.dart';
import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/addon_entity.dart';
import '../../domain/entities/ota_update.dart';
import '../../domain/repositories/manage_app_updates.dart';
import '../../domain/repositories/resolve_movie_streams.dart';
import '../network/http_transport.dart';
import 'memory_cache_service.dart';
import '../network/http_connection_pool.dart';
import 'power_management_service.dart';

final class AppDependencies {
  const AppDependencies._({
    required http.Client? client,
    required HttpConnectionPool? pool,
    required http.Client? updateClient,
    required this.updates,
    required this.power,
    required this.addons,
    required this.iptv,
    required this.library,
    required this.media,
    required this.streams,
    required this.subtitles,
    required LocalPlaybackPreferencesRepository playbackPreferences,
  }) : _client = client,
       _pool = pool,
       _updateClient = updateClient,
       _playbackPreferences = playbackPreferences;

  final http.Client? _client;
  final HttpConnectionPool? _pool;
  final http.Client? _updateClient;
  final ManageAppUpdates? updates;
  final PowerManagementService power;
  final LocalPlaybackPreferencesRepository _playbackPreferences;
  final AddonRepository addons;
  final IptvRepository iptv;
  final MediaLibraryRepository library;
  final MediaRepository media;
  final StreamManager streams;
  final SubtitleRepository subtitles;

  ResolveMovieStreams get resolveMovieStreams => ResolveMovieStreams(streams);
  PlaybackPreferencesRepository get playbackPreferences => _playbackPreferences;

  /// Asume el ciclo de vida del cliente HTTP, incluso si se inyecta uno.
  factory AppDependencies.create([http.Client? client]) {
    WebOsVideoPlayer.configure();
    final updatePlatform = switch (VideoPlayerPlatform.instance) {
      WebOsVideoPlayer() => OtaPlatform.webos,
      _ when !kIsWeb && defaultTargetPlatform == TargetPlatform.android =>
        OtaPlatform.android,
      _ => null,
    };
    final manifest = Uri.tryParse(
      const String.fromEnvironment('OTA_MANIFEST_URL'),
    );
    final updateClient =
        updatePlatform != null &&
            manifest != null &&
            manifest.scheme == 'https' &&
            manifest.host.isNotEmpty &&
            manifest.userInfo.isEmpty &&
            !manifest.hasFragment
        ? http.Client()
        : null;
    final imageCache = MemoryCacheService()..configure();
    final pool = client == null ? HttpConnectionPool(http.Client.new) : null;
    final transport = client == null
        ? HttpTransport.managed(pool!)
        : HttpTransport(client);
    final updates = switch (updatePlatform) {
      final platform? => ManageAppUpdates(
        OtaUpdaterAdapter(
          updateClient,
          platform: platform,
          manifest: updateClient == null ? null : manifest,
        ),
        isConfigured: updateClient != null,
      ),
      _ when kIsWeb => ManageAppUpdates.localOnly(
        () => OtaUpdaterAdapter.readWebVersion(transport),
      ),
      _ => null,
    };
    final api = JsonApi(transport);
    const accessToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
    final tmdb = TmdbRepository(api, accessToken: accessToken);
    final providers = <AddonEntity, StreamProviderContract>{
      AddonEntity(
        id: 'demo',
        name: 'Video de prueba',
        baseUrl: Uri.parse(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
        ),
        isEnabled: true,
        priority: 1,
      ): const DemoStreamProvider(),
      AddonEntity(
        id: 'torrentio',
        name: 'Torrentio',
        baseUrl: Uri.parse(
          const String.fromEnvironment(
            'TORRENTIO_BASE_URL',
            defaultValue: 'https://torrentio.strem.fun',
          ),
        ),
        isEnabled: false,
        priority: 2,
      ): TorrentioAdapter(
        api,
        resolveImdbId: tmdb.findImdbId,
      ),
    };

    final preferences = SharedPreferencesAsync();
    final addons = LocalAddonRepository(preferences, defaults: providers.keys);
    final streams = StreamManager(addons: addons);
    for (final entry in providers.entries) {
      streams.register(entry.key.id, entry.value);
    }
    return AppDependencies._(
      client: client,
      pool: pool,
      updateClient: updateClient,
      updates: updates,
      power: PowerManagementService(
        onSuspendNetwork: pool?.suspend,
        onResumeNetwork: pool?.resume,
        imageCache: imageCache,
      ),
      addons: addons,
      iptv: LocalIptvRepository(preferences, M3uPlaylistLoader(transport)),
      library: LocalMediaLibraryRepository(preferences),
      media: accessToken.isEmpty ? DemoMediaRepository() : tmdb,
      streams: streams,
      subtitles: HttpSubtitleRepository(transport),
      playbackPreferences: LocalPlaybackPreferencesRepository(preferences),
    );
  }

  void dispose() {
    power.dispose();
    _pool?.close();
    _client?.close();
    _updateClient?.close();
  }
}
