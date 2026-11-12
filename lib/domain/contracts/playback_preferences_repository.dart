abstract interface class PlaybackPreferencesRepository {
  Future<bool> getShowDeveloperStreamLinks();

  Future<void> setShowDeveloperStreamLinks(bool enabled);

  Future<bool> getIptvEnabled();

  Future<void> setIptvEnabled(bool enabled);
}
