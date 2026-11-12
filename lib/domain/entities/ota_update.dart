enum OtaPlatform { android, webos }

final class OtaUpdate {
  const OtaUpdate({
    required this.platform,
    required this.version,
    required this.url,
    required this.sha256,
    required this.bytes,
    this.build,
    this.publishedAt,
    this.releaseNotes = const [],
    this.mandatory = false,
  });

  final OtaPlatform platform;
  final String version;
  final Uri url;
  final String sha256;
  final int bytes;
  final int? build;
  final DateTime? publishedAt;
  final List<String> releaseNotes;
  final bool mandatory;
}

enum OtaStage { downloading, verifying, installerOpened, permissionRequired }

final class OtaProgress {
  const OtaProgress(this.stage, {this.fraction});

  final OtaStage stage;
  final double? fraction;
}
