import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/network/http_transport.dart';
import '../../domain/contracts/ota_repository.dart';
import '../../domain/entities/ota_update.dart';

final class OtaUpdaterAdapter implements OtaRepository {
  OtaUpdaterAdapter(
    this._client, {
    required this.platform,
    this.manifest,
    this.webOsVersion,
  }) {
    if (manifest case final uri? when !_isHttps(uri)) {
      throw ArgumentError('El manifiesto OTA debe usar HTTPS.');
    }
  }

  static const _android = MethodChannel('l3loow/ota_updater');
  static const _networkTimeout = Duration(seconds: 15);
  static const _maxManifestBytes = 64 * 1024;
  static const _maxPackageBytes = 512 * 1024 * 1024;
  static final _version = RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$');
  static final _digest = RegExp(r'^[a-fA-F0-9]{64}$');

  final http.Client? _client;
  final Uri? manifest;
  final String? webOsVersion;
  @override
  final OtaPlatform platform;
  bool _installing = false;

  static Future<({String version, int? build})> readWebVersion(
    HttpTransport transport,
  ) async {
    final bytes = await transport.get(
      Uri.base.resolve('version.json'),
      maxBytes: _maxManifestBytes,
    );
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return (
      version: data['version'] as String,
      build: int.tryParse('${data['build_number']}'),
    );
  }

  @override
  Future<({String version, int? build})> installedVersion() async {
    if (platform == OtaPlatform.webos) {
      final version =
          webOsVersion ??
          (jsonDecode(await rootBundle.loadString('webos/meta/appinfo.json'))
              as Map<String, dynamic>)['version'];
      if (version is! String || !_version.hasMatch(version)) {
        throw const FormatException('Versión webOS inválida.');
      }
      return (
        version: version,
        build: int.tryParse(const String.fromEnvironment('WEBOS_BUILD_NUMBER')),
      );
    }
    final installed = await _android.invokeMapMethod<String, Object?>(
      'installedVersion',
    );
    return (
      version: installed!['version'] as String,
      build: installed['build'] as int,
    );
  }

  @override
  Future<OtaUpdate?> latestRelease() async {
    final manifest = this.manifest;
    if (manifest == null) return null;
    final response = await _get(manifest, accept: 'application/json');
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(_networkTimeout)) {
      if (buffer.length + chunk.length > _maxManifestBytes) {
        throw const FormatException('Manifiesto OTA demasiado grande.');
      }
      buffer.add(chunk);
    }
    final data = jsonDecode(utf8.decode(buffer.takeBytes()));
    if (data is! Map<String, dynamic> || data['schema'] != 1) {
      throw const FormatException('Esquema OTA inválido.');
    }
    final release = data[platform.name];
    if (release == null) return null;
    if (release case {
      'version': final String version,
      'url': final String url,
      'sha256': final String digest,
      'bytes': final int bytes,
    }) {
      final uri = manifest.resolve(url);
      final build = release['build'];
      final extension = platform == OtaPlatform.android ? '.apk' : '.ipk';
      if (_version.hasMatch(version) &&
          _digest.hasMatch(digest) &&
          bytes > 0 &&
          bytes <= _maxPackageBytes &&
          _isHttps(uri) &&
          _allowsArtifact(manifest, uri) &&
          uri.path.toLowerCase().endsWith(extension) &&
          (platform != OtaPlatform.android || (build is int && build > 0))) {
        return OtaUpdate(
          platform: platform,
          version: version,
          url: uri,
          sha256: digest.toLowerCase(),
          bytes: bytes,
          build: build is int ? build : null,
          publishedAt: switch (release['publishedAt'] ?? data['publishedAt']) {
            final String value => DateTime.tryParse(value),
            _ => null,
          },
          releaseNotes: _parseNotes(
            release['releaseNotes'] ?? data['releaseNotes'],
          ),
          mandatory: (release['mandatory'] ?? data['mandatory']) == true,
        );
      }
    }
    throw const FormatException('Paquete OTA inválido.');
  }

  static List<String> _parseNotes(Object? value) {
    if (value is! List) return const [];
    return List.unmodifiable(
      value
          .whereType<String>()
          .map((note) => note.trim())
          .where((note) => note.isNotEmpty),
    );
  }

  @override
  Stream<OtaProgress> install(OtaUpdate update) async* {
    final manifest = this.manifest;
    if (manifest == null ||
        platform != OtaPlatform.android ||
        update.platform != platform ||
        !_isHttps(update.url) ||
        !_allowsArtifact(manifest, update.url) ||
        !update.url.path.toLowerCase().endsWith('.apk') ||
        !_digest.hasMatch(update.sha256) ||
        update.bytes <= 0 ||
        update.bytes > _maxPackageBytes ||
        update.build == null) {
      throw StateError('Paquete Android inválido.');
    }
    if (_installing) throw StateError('Ya hay una descarga OTA en curso.');
    _installing = true;
    File? file;
    var handedOff = false;
    try {
      if (await _android.invokeMethod<bool>('authorize') != true) {
        yield const OtaProgress(OtaStage.permissionRequired);
        return;
      }
      final path = await _android.invokeMethod<String>('createPackageFile');
      file = File(path!);
      yield const OtaProgress(OtaStage.downloading, fraction: 0);
      final output = await file.open(mode: FileMode.writeOnly);
      var downloaded = 0;
      var lastPercent = 0;
      try {
        final response = await _get(update.url);
        await for (final chunk in response.stream.timeout(_networkTimeout)) {
          downloaded += chunk.length;
          if (downloaded > update.bytes) {
            throw const FormatException('Tamaño del APK inválido.');
          }
          await output.writeFrom(chunk);
          final percent = downloaded * 100 ~/ update.bytes;
          if (percent > lastPercent) {
            lastPercent = percent;
            yield OtaProgress(OtaStage.downloading, fraction: percent / 100);
          }
        }
      } finally {
        await output.close();
      }
      if (downloaded != update.bytes) {
        throw const FormatException('Descarga del APK incompleta.');
      }
      yield const OtaProgress(OtaStage.verifying);
      final actual = await sha256.bind(file.openRead()).first;
      if (actual.toString() != update.sha256.toLowerCase()) {
        throw const FormatException('SHA-256 del APK inválido.');
      }
      await _android.invokeMethod<void>('install', {
        'path': file.path,
        'build': update.build,
      });
      handedOff = true;
      yield const OtaProgress(OtaStage.installerOpened);
    } finally {
      _installing = false;
      if (!handedOff && file != null && await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<http.StreamedResponse> _get(Uri uri, {String? accept}) async {
    final releaseRepo = _gitHubReleaseRepo(uri);
    for (var hop = 0; ; hop++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      if (accept != null) {
        request.headers['accept'] = accept;
        request.headers['cache-control'] = 'no-cache';
      }
      final response = await _client!.send(request).timeout(_networkTimeout);
      if (response.statusCode == 200) return response;
      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      if (releaseRepo != null &&
          hop < 3 &&
          const {301, 302, 303, 307, 308}.contains(response.statusCode) &&
          location != null) {
        final next = uri.resolve(location);
        if (_isHttps(next) &&
            next.port == 443 &&
            (_gitHubReleaseRepo(next) == releaseRepo ||
                const {
                  'release-assets.githubusercontent.com',
                  'objects.githubusercontent.com',
                }.contains(next.host))) {
          uri = next;
          continue;
        }
      }
      throw HttpException('HTTP ${response.statusCode}');
    }
  }

  static bool _allowsArtifact(Uri manifest, Uri artifact) {
    final releaseRepo = _gitHubReleaseRepo(manifest);
    if (releaseRepo != null) return releaseRepo == _gitHubReleaseRepo(artifact);
    if (manifest.origin == artifact.origin) return true;
    final repo = _gitHubReleaseRepo(artifact);
    return repo != null &&
        manifest.host == 'raw.githubusercontent.com' &&
        manifest.port == 443 &&
        repo == _repo(manifest);
  }

  static String? _gitHubReleaseRepo(Uri uri) {
    final path = uri.pathSegments;
    if (uri.host != 'github.com' ||
        uri.port != 443 ||
        path.length < 6 ||
        path[2] != 'releases' ||
        (path[3] != 'download' &&
            !(path[3] == 'latest' && path[4] == 'download'))) {
      return null;
    }
    return _repo(uri);
  }

  static String? _repo(Uri uri) {
    final path = uri.pathSegments;
    if (path.length < 2) return null;
    return '${path[0]}/${path[1]}'.toLowerCase();
  }

  static bool _isHttps(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;
}
