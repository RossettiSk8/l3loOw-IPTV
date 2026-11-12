import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/playback_preferences_repository.dart';

final class LocalPlaybackPreferencesRepository
    implements PlaybackPreferencesRepository {
  const LocalPlaybackPreferencesRepository(this._preferences);

  static const _developerLinksKey = 'showDeveloperStreamLinks';
  static const _iptvEnabledKey = 'iptv.enabled';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> getShowDeveloperStreamLinks() async =>
      await _preferences.getBool(_developerLinksKey) ?? false;

  @override
  Future<void> setShowDeveloperStreamLinks(bool enabled) =>
      _preferences.setBool(_developerLinksKey, enabled);

  @override
  Future<bool> getIptvEnabled() async =>
      await _preferences.getBool(_iptvEnabledKey) ?? false;

  @override
  Future<void> setIptvEnabled(bool enabled) =>
      _preferences.setBool(_iptvEnabledKey, enabled);
}
