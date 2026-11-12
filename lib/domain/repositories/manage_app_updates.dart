import '../contracts/ota_repository.dart';
import '../entities/ota_update.dart';

typedef InstalledAppVersion = ({String version, int? build});

final class ManageAppUpdates {
  const ManageAppUpdates(OtaRepository repository, {this.isConfigured = true})
    : _repository = repository,
      _readLocalVersion = null;

  const ManageAppUpdates.localOnly(
    Future<InstalledAppVersion> Function() readVersion,
  ) : _repository = null,
      _readLocalVersion = readVersion,
      isConfigured = false;

  final OtaRepository? _repository;
  final Future<InstalledAppVersion> Function()? _readLocalVersion;
  final bool isConfigured;

  Future<InstalledAppVersion> installedVersion() =>
      _readLocalVersion?.call() ?? _repository!.installedVersion();

  Future<OtaUpdate?> check() async {
    final repository = _repository;
    if (!isConfigured || repository == null) return null;
    final installed = await installedVersion();
    final release = await repository.latestRelease();
    if (release == null) return null;

    final newer = switch (repository.platform) {
      OtaPlatform.android => release.build! > installed.build!,
      OtaPlatform.webos => _isNewer(release.version, installed.version),
    };
    return newer ? release : null;
  }

  Stream<OtaProgress> install(OtaUpdate update) {
    final repository = _repository;
    if (!isConfigured || repository == null) {
      return Stream.error(
        StateError('El canal de actualizaciones no está disponible.'),
      );
    }
    return repository.install(update);
  }

  static bool _isNewer(String remote, String installed) {
    final target = remote.split('.').map(int.parse).toList();
    final current = installed.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      if (target[index] != current[index]) {
        return target[index] > current[index];
      }
    }
    return false;
  }
}
