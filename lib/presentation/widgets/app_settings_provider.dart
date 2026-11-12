import 'package:flutter/widgets.dart';

import '../../domain/contracts/media_library_repository.dart';
import '../../domain/contracts/playback_preferences_repository.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/manage_app_updates.dart';

final class AppSettingsProvider extends InheritedNotifier<AppSettings> {
  const AppSettingsProvider({
    required AppSettings settings,
    this.updates,
    required super.child,
    super.key,
  }) : super(notifier: settings);

  final ManageAppUpdates? updates;

  static ManageAppUpdates? updatesOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppSettingsProvider>()
      ?.updates;

  @override
  bool updateShouldNotify(AppSettingsProvider oldWidget) =>
      updates != oldWidget.updates || super.updateShouldNotify(oldWidget);

  static AppSettings of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppSettingsProvider>()!
      .notifier!;
}

final class AppSettings extends ChangeNotifier {
  AppSettings(
    PlaybackPreferencesRepository repository, {
    MediaLibraryRepository? library,
  }) : _developerLinks = _BooleanSetting(
         repository.setShowDeveloperStreamLinks,
       ),
       _iptv = _BooleanSetting(repository.setIptvEnabled),
       _library = library {
    _load(repository);
    _loadLibrary();
  }

  final _BooleanSetting _developerLinks;
  final _BooleanSetting _iptv;
  final MediaLibraryRepository? _library;
  List<MediaItem> _savedTitles = const [];
  bool _libraryReady = false;
  bool _savingTitle = false;
  bool _isReady = false;
  bool _disposed = false;

  bool get showDeveloperStreamLinks => _developerLinks.value;
  bool get iptvEnabled => _iptv.value;
  bool get isReady => _isReady;
  bool get libraryReady => _libraryReady;
  List<MediaItem> get savedTitles => _savedTitles;

  bool isSaved(MediaItem title) => _savedTitles.any(
    (item) => item.id == title.id && item.kind == title.kind,
  );

  Future<void> _loadLibrary() async {
    try {
      _savedTitles = List.unmodifiable(await _library?.list() ?? []);
    } catch (_) {
      // Mantiene los datos existentes si falla la lectura.
      return;
    }
    if (_disposed) return;
    _libraryReady = true;
    notifyListeners();
  }

  Future<void> toggleSaved(MediaItem title) async {
    if (_disposed || !_libraryReady || _savingTitle) return;
    final updated = isSaved(title)
        ? _savedTitles
              .where((item) => item.id != title.id || item.kind != title.kind)
              .toList()
        : [title, ..._savedTitles];
    _savingTitle = true;
    try {
      await _library?.save(updated);
      if (_disposed) return;
      _savedTitles = List.unmodifiable(updated);
      notifyListeners();
    } finally {
      _savingTitle = false;
    }
  }

  Future<void> _load(PlaybackPreferencesRepository repository) async {
    await Future.wait([
      _developerLinks.load(repository.getShowDeveloperStreamLinks),
      _iptv.load(repository.getIptvEnabled),
    ]);
    if (_disposed) return;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setShowDeveloperStreamLinks(bool enabled) =>
      _set(_developerLinks, enabled);

  Future<void> setIptvEnabled(bool enabled) => _set(_iptv, enabled);

  Future<void> _set(_BooleanSetting setting, bool enabled) async {
    if (_disposed || !_isReady) return;
    await setting.update(enabled, () {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _BooleanSetting {
  _BooleanSetting(this._write);

  final Future<void> Function(bool) _write;
  bool value = false;
  bool _persisted = false;
  Future<void> _pendingWrite = Future.value();
  int _revision = 0;

  Future<void> load(Future<bool> Function() read) async {
    try {
      value = _persisted = await read();
    } catch (_) {
      // El ajuste sigue disponible con su valor inicial.
    }
  }

  Future<void> update(bool enabled, VoidCallback onChanged) async {
    if (enabled == value) return;
    final revision = ++_revision;
    value = enabled;
    final write = _pendingWrite.then((_) async {
      await _write(enabled);
      _persisted = enabled;
    });
    _pendingWrite = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    onChanged();
    try {
      await write;
    } catch (_) {
      if (revision != _revision) return;
      value = _persisted;
      onChanged();
      rethrow;
    }
  }
}
