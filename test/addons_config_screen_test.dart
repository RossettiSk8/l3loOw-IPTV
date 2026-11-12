import 'dart:async';

import 'package:app_streaming/core/dependencies/app_constants.dart';
import 'package:app_streaming/domain/contracts/playback_preferences_repository.dart';
import 'package:app_streaming/main.dart';
import 'package:app_streaming/presentation/widgets/app_settings_provider.dart';
import 'package:app_streaming/presentation/widgets/tv_action.dart';
// Usa la misma biblioteca de Material que la aplicación en el SDK de LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test(
    'Publica los cambios antes de guardar y persiste el último valor',
    () async {
      final repository = _DelayedPreferences();
      final settings = AppSettings(repository);
      addTearDown(settings.dispose);
      final ready = Completer<void>();
      settings.addListener(() {
        if (!ready.isCompleted) ready.complete();
      });
      await ready.future;

      final enable = settings.setShowDeveloperStreamLinks(true);
      expect(settings.showDeveloperStreamLinks, isTrue);
      final disable = settings.setShowDeveloperStreamLinks(false);
      expect(settings.showDeveloperStreamLinks, isFalse);
      expect(repository.saved, isEmpty);

      repository.firstWrite.complete();
      await Future.wait([enable, disable]);
      expect(repository.saved, [true, false]);
      expect(settings.showDeveloperStreamLinks, isFalse);
    },
  );

  testWidgets('Guarda la activación y el orden al volver a abrir la app', (
    tester,
  ) async {
    final original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);

    await tester.pumpWidget(const AppStreaming());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile, skipOffstage: false), findsNWidgets(4));
    final developerSwitch = find.widgetWithText(
      SwitchListTile,
      'Modo desarrollador',
    );
    expect(tester.widget<SwitchListTile>(developerSwitch).value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.ensureVisible(developerSwitch);
    await tester.tap(developerSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(developerSwitch).value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const AppStreaming());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Complementos'));
    await tester.pumpAndSettle();

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile, skipOffstage: false),
    );
    expect(switches.map((tile) => (tile.title as Text).data), [
      'Torrentio',
      'Video de prueba',
      'Modo desarrollador',
      'Activar IPTV',
    ]);
    expect(switches.map((tile) => tile.value), [false, false, true, false]);
    await tester.ensureVisible(developerSwitch);
    await tester.tap(developerSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(developerSwitch).value, isFalse);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);
  });

  testWidgets('Inicio y Ajustes consultan el mismo manifiesto OTA fijo', (
    tester,
  ) async {
    final original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('l3loow/ota_updater');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'installedVersion');
      return {'version': '1.0.0', 'build': 17};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final requests = <Uri>[];
    final endpoint = Uri.parse(AppConstants.otaManifestUrl);
    await http.runWithClient(
      () => tester.pumpWidget(const AppStreaming()),
      () => MockClient.streaming((request, _) async {
        requests.add(request.url);
        return http.StreamedResponse(
          Stream.value('{"schema":1}'.codeUnits),
          200,
        );
      }),
    );
    await tester.pumpAndSettle();
    expect(requests, [endpoint]);

    await tester.tap(find.byTooltip('Complementos'));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TvAction && widget.label == 'Buscar actualizaciones',
    );
    await tester.scrollUntilVisible(
      search,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Versión 1.0.0 · Compilación 17'), findsOneWidget);
    await tester.tap(search);
    await tester.pump();
    expect(requests, [endpoint, endpoint]);
    // La lectura del cuerpo HTTP también pasa por el bucle de eventos real.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('l3loOw está actualizado.'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}

final class _DelayedPreferences implements PlaybackPreferencesRepository {
  final firstWrite = Completer<void>();
  final saved = <bool>[];

  @override
  Future<bool> getShowDeveloperStreamLinks() async => false;

  @override
  Future<void> setShowDeveloperStreamLinks(bool enabled) async {
    if (saved.isEmpty) await firstWrite.future;
    saved.add(enabled);
  }

  @override
  Future<bool> getIptvEnabled() async => false;

  @override
  Future<void> setIptvEnabled(bool enabled) async {}
}
