import '../entities/ota_update.dart';

abstract interface class OtaRepository {
  OtaPlatform get platform;
  Future<({String version, int? build})> installedVersion();
  Future<OtaUpdate?> latestRelease();
  Stream<OtaProgress> install(OtaUpdate update);
}
