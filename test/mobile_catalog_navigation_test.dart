import 'package:app_streaming/presentation/widgets/mobile_catalog_navigation.dart';
import 'package:app_streaming/presentation/widgets/streaming_theme.dart';
import 'package:app_streaming/presentation/widgets/tv_action.dart';
// Usa la misma biblioteca de Material que la aplicación en el SDK de LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Redistribuye el ancho y revela solo la etiqueta activa', (
    tester,
  ) async {
    await _mountDock(tester);
    final home = _action('Inicio');
    final search = _action('Buscar');
    final profile = _action('Perfil');
    final expanded = tester.getSize(home).width;
    final compact = tester.getSize(search).width;
    expect(expanded, greaterThan(compact));
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Buscar'), findsNothing);

    await tester.tap(search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final halfway = tester.getSize(search).width;
    expect(halfway, inExclusiveRange(compact, expanded));
    expect(tester.getSize(home).width, inExclusiveRange(compact, expanded));
    expect(tester.getSize(_action('Biblioteca')).width, compact);

    await tester.tap(profile);
    await tester.pump();
    expect(tester.getSize(search).width, closeTo(halfway, 0.1));
    await tester.pumpAndSettle();
    expect(tester.getSize(profile).width, closeTo(expanded, 0.1));
    expect(tester.getSize(search).width, compact);
    expect(tester.widget<TvAction>(profile).selected, isTrue);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
    expect(find.text('Buscar'), findsNothing);
    expect(find.text('Biblioteca'), findsNothing);
  });

  testWidgets(
    'Permite seleccionar con el mando y respeta movimiento reducido',
    (tester) async {
      await _mountDock(tester, reduceMotion: true);
      final expanded = tester.getSize(_action('Inicio')).width;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.widget<TvAction>(_action('Buscar')).selected, isTrue);
      expect(tester.getSize(_action('Buscar')).width, closeTo(expanded, 0.1));
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Inicio'), findsNothing);
    },
  );
}

Finder _action(String label) => find.byWidgetPredicate(
  (widget) => widget is TvAction && widget.label == label,
);

Future<void> _mountDock(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(300, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final destination = ValueNotifier(MobileDestination.home);
  addTearDown(destination.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: streamingTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder(
                valueListenable: destination,
                builder: (context, current, _) => MobileCatalogNavigation(
                  selected: current,
                  onSelected: (item) => destination.value = item,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
