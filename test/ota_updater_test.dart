import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_streaming/data/adapters/ota_updater_adapter.dart';
import 'package:app_streaming/domain/contracts/ota_repository.dart';
import 'package:app_streaming/domain/entities/ota_update.dart';
import 'package:app_streaming/domain/repositories/manage_app_updates.dart';
import 'package:app_streaming/presentation/widgets/ota_update_dialog.dart';
import 'package:app_streaming/presentation/widgets/tv_action.dart';
import 'package:app_streaming/presentation/widgets/version_updates_panel.dart';
import 'package:crypto/crypto.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = Uri.parse('https://releases.example/ota/manifest.json');
  final apk = [1, 2, 3, 4];
  final channel = const MethodChannel('l3loow/ota_updater');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Directory temporary;
  late File file;
  late bool authorized;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('l3loow-ota-test');
    file = File('${temporary.path}/package.apk');
    calls.clear();
    authorized = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'installedVersion' => {'version': '0.1.0', 'build': 10},
        'authorize' => authorized,
        'createPackageFile' => file.path,
        'install' => null,
        _ => throw MissingPluginException(),
      };
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  ManageAppUpdates create({
    OtaPlatform platform = OtaPlatform.android,
    String installed = '0.9.1',
    String version = '0.10.0',
    int build = 11,
    String? url,
    List<int>? body,
    int packageStatus = 200,
    Uri? endpoint,
    String? redirect,
    Map<String, Object?> metadata = const {},
    Map<String, Object?> platformMetadata = const {},
  }) {
    final source = endpoint ?? manifest;
    final extension = platform == OtaPlatform.android ? 'apk' : 'ipk';
    return ManageAppUpdates(
      OtaUpdaterAdapter(
        MockClient.streaming((request, _) async {
          expect(request.followRedirects, isFalse);
          if (request.url == source) {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'schema': 1,
                    ...metadata,
                    platform.name: {
                      'version': version,
                      'build': build,
                      'url': url ?? 'release.$extension',
                      'bytes': apk.length,
                      'sha256': sha256.convert(apk).toString(),
                      ...platformMetadata,
                    },
                  }),
                ),
              ),
              200,
            );
          }
          if (redirect != null && request.url.host == 'github.com') {
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: {'location': redirect},
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              (body ?? apk).take(2).toList(),
              (body ?? apk).skip(2).toList(),
            ]),
            packageStatus,
          );
        }),
        platform: platform,
        manifest: source,
        webOsVersion: installed,
      ),
    );
  }

  test(
    'Android compara versionCode y webOS compara la versión numérica',
    () async {
      expect(await create(build: 10).check(), isNull);
      expect(await create(build: 9).check(), isNull);
      expect((await create().check())?.build, 11);
      final ipk = await create(platform: OtaPlatform.webos).check();
      expect(ipk?.url, manifest.resolve('release.ipk'));
      expect(
        await create(platform: OtaPlatform.webos, installed: '0.10.0').check(),
        isNull,
      );
    },
  );

  test('Rechaza artefactos externos o con extensión inválida', () async {
    for (final url in ['https://elsewhere.example/update.apk', 'release.ipk']) {
      await expectLater(create(url: url).check(), throwsFormatException);
    }
  });

  test('Lee los metadatos del modal y admite manifiestos anteriores', () async {
    final legacy = (await create().check())!;
    expect(legacy.mandatory, isFalse);
    expect(legacy.publishedAt, isNull);
    expect(legacy.releaseNotes, isEmpty);

    final release = (await create(
      metadata: {
        'publishedAt': '2026-11-12',
        'releaseNotes': ['Mejoras generales'],
        'mandatory': true,
      },
      platformMetadata: {
        'releaseNotes': ['Arranque más rápido', '', 3],
        'mandatory': false,
      },
    ).check())!;
    expect(release.publishedAt, DateTime(2026, 11, 12));
    expect(release.releaseNotes, ['Arranque más rápido']);
    expect(release.mandatory, isFalse);
    expect(
      (await create(metadata: {'mandatory': true}).check())!.mandatory,
      isTrue,
    );
  });

  test(
    'Descarga por bloques, verifica y entrega el APK al instalador',
    () async {
      final updater = create();
      final release = (await updater.check())!;
      final progress = await updater.install(release).toList();
      expect(
        progress
            .where((event) => event.stage == OtaStage.downloading)
            .map((event) => event.fraction),
        [0, 0.5, 1],
      );
      expect(progress[3].stage, OtaStage.verifying);
      expect(progress.last.stage, OtaStage.installerOpened);
      expect(calls.last.method, 'install');
      expect(calls.last.arguments, {'path': file.path, 'build': 11});
      expect(await file.readAsBytes(), apk);
    },
  );

  test('Borra el APK incompleto o corrupto y nunca lo instala', () async {
    for (final body in [
      [1, 2],
      [0, 0, 0, 0],
    ]) {
      final updater = create(body: body);
      final release = (await updater.check())!;
      await expectLater(
        updater.install(release).drain<void>(),
        throwsFormatException,
      );
      expect(await file.exists(), isFalse);
    }
    expect(calls.map((call) => call.method), isNot(contains('install')));
  });

  test('La falta de permiso no inicia una descarga', () async {
    authorized = false;
    final updater = create();
    final release = (await updater.check())!;
    final progress = await updater.install(release).toList();
    expect(progress.single.stage, OtaStage.permissionRequired);
    expect(calls.map((call) => call.method), ['installedVersion', 'authorize']);
    expect(await file.exists(), isFalse);
  });

  test('El binario no sigue redirecciones', () async {
    final updater = create(packageStatus: 302);
    final release = (await updater.check())!;
    await expectLater(
      updater.install(release).drain<void>(),
      throwsA(isA<HttpException>()),
    );
    expect(await file.exists(), isFalse);
    expect(calls.map((call) => call.method), isNot(contains('install')));
  });

  test(
    'Un manifiesto Raw admite artefactos del release del mismo repositorio',
    () async {
      final raw = Uri.parse(
        'https://raw.githubusercontent.com/org/app/main/version.json',
      );
      const apkUrl =
          'https://github.com/org/app/releases/download/v1.1.0/update.apk';
      final updater = create(
        endpoint: raw,
        url: apkUrl,
        redirect:
            'https://release-assets.githubusercontent.com/assets/file?sig=mock',
      );
      final release = (await updater.check())!;
      expect(
        (await updater.install(release).last).stage,
        OtaStage.installerOpened,
      );

      await expectLater(
        create(
          endpoint: raw,
          url: apkUrl.replaceFirst('/org/app/', '/org/other/'),
        ).check(),
        throwsFormatException,
      );

      final external = create(
        endpoint: raw,
        url: apkUrl,
        redirect: 'https://elsewhere.example/update.apk',
      );
      await expectLater(
        external.install((await external.check())!).drain<void>(),
        throwsA(isA<HttpException>()),
      );
    },
  );

  testWidgets(
    'La búsqueda manual muestra carga y abre el flujo con una versión nueva',
    (tester) async {
      final pending = Completer<OtaUpdate?>();
      final repository = _BannerRepository(release: pending.future);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VersionUpdatesPanel(updates: ManageAppUpdates(repository)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Versión 0.1.0 · Compilación 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Buscando actualizaciones…'), findsOneWidget);
      pending.complete(_BannerRepository.available);
      await tester.pumpAndSettle();
      expect(find.text('Nueva versión disponible'), findsOneWidget);
      expect(find.text('Actualizar ahora'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      repository.progress.add(
        const OtaProgress(OtaStage.downloading, fraction: 0.5),
      );
      await tester.pump();
      expect(find.text('Descargando · 50 %'), findsOneWidget);
      expect(find.text('Actualizar ahora'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );
      repository.progress.add(const OtaProgress(OtaStage.verifying));
      await tester.pump();
      expect(find.text('Verificando SHA-256…'), findsOneWidget);
      repository.progress.add(const OtaProgress(OtaStage.installerOpened));
      unawaited(repository.progress.close());
      await tester.pumpAndSettle();
      expect(find.text('Confirma la instalación en Android.'), findsOneWidget);
    },
  );

  testWidgets('La búsqueda manual informa si no hay una versión más reciente', (
    tester,
  ) async {
    final repository = _BannerRepository(release: Future.value());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VersionUpdatesPanel(updates: ManageAppUpdates(repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvAction && widget.label == 'Buscar actualizaciones',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('l3loOw está actualizado.'), findsOneWidget);
  });

  testWidgets('El modal se abre una vez al iniciar y se aplaza con el mando', (
    tester,
  ) async {
    final repository = _BannerRepository(
      release: Future.value(_BannerRepository.releaseFor()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OtaStartupCheck(
          updates: ManageAppUpdates(repository),
          child: const Scaffold(body: Text('Catálogo')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OtaUpdateDialog), findsOneWidget);
    expect(find.text('ACTUALIZACIÓN DISPONIBLE'), findsOneWidget);
    expect(find.text('Versión 0.2.0 · 12/11/2026'), findsOneWidget);
    expect(find.text('Novedades y mejoras'), findsOneWidget);
    expect(find.text('Arranque más rápido'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(OtaUpdateDialog), findsNothing);
    expect(find.text('Catálogo'), findsOneWidget);
    expect(repository.checks, 1);
    expect(repository.installs, 0);
  });

  testWidgets(
    'Una actualización obligatoria permanece abierta al pulsar Atrás',
    (tester) async {
      final repository = _BannerRepository(
        release: Future.value(_BannerRepository.releaseFor(mandatory: true)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OtaStartupCheck(
            updates: ManageAppUpdates(repository),
            child: const Scaffold(body: Text('Catálogo')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VERSIÓN NO COMPATIBLE'), findsOneWidget);
      expect(find.text('Más tarde'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(OtaUpdateDialog), findsOneWidget);
    },
  );

  testWidgets(
    'El modal de webOS muestra el IPK para la instalación autorizada',
    (tester) async {
      final release = _BannerRepository.releaseFor(platform: OtaPlatform.webos);
      final repository = _BannerRepository(
        platform: OtaPlatform.webos,
        release: Future.value(release),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OtaStartupCheck(
            updates: ManageAppUpdates(repository),
            child: const Scaffold(body: Text('Catálogo')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text(release.url.toString()), findsOneWidget);
      expect(repository.installs, 0);
    },
  );
}

final class _BannerRepository implements OtaRepository {
  _BannerRepository({this.release, this.platform = OtaPlatform.android});

  final Future<OtaUpdate?>? release;
  final progress = StreamController<OtaProgress>();
  int checks = 0;
  int installs = 0;

  @override
  final OtaPlatform platform;

  @override
  Future<({int? build, String version})> installedVersion() async =>
      (version: '0.1.0', build: 1);

  @override
  Future<OtaUpdate?> latestRelease() {
    checks++;
    return release ?? Future.value(available);
  }

  static final available = releaseFor();

  static OtaUpdate releaseFor({
    OtaPlatform platform = OtaPlatform.android,
    bool mandatory = false,
  }) => OtaUpdate(
    platform: platform,
    version: '0.2.0',
    build: 2,
    url: Uri.https(
      'releases.example',
      platform == OtaPlatform.android ? '/release.apk' : '/release.ipk',
    ),
    sha256: '',
    bytes: 1,
    mandatory: mandatory,
    publishedAt: DateTime(2026, 11, 12),
    releaseNotes: const ['Arranque más rápido'],
  );

  @override
  Stream<OtaProgress> install(OtaUpdate update) {
    installs++;
    return progress.stream;
  }
}
