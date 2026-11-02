import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/widgets/focus_tooltips.dart';

Future<void> _pump(WidgetTester tester, {bool enabled = true}) async {
  await tester.pumpWidget(FocusTooltips(
    enabled: enabled,
    child: MaterialApp(
      theme: PlayerTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                autofocus: true,
                tooltip: 'Biblioteca',
                icon: const Icon(Icons.video_library_outlined),
                onPressed: () {},
              ),
              IconButton(
                tooltip: 'Favoritos',
                icon: const Icon(Icons.favorite_outline),
                onPressed: () {},
              ),
              TextButton(onPressed: () {}, child: const Text('Sem balão')),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _arrow(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('foco inicial da tela não mostra balão', (tester) async {
    await _pump(tester);

    expect(find.text('Biblioteca'), findsNothing);
  });

  testWidgets('seta mostra o balão e ele acompanha a seleção', (tester) async {
    await _pump(tester);

    await _arrow(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Favoritos'), findsOneWidget);

    await _arrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('sair para um controle sem nome esconde o balão', (tester) async {
    await _pump(tester);

    await _arrow(tester, LogicalKeyboardKey.arrowRight);
    await _arrow(tester, LogicalKeyboardKey.arrowRight);

    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('balão some sozinho depois de um tempo', (tester) async {
    await _pump(tester);

    await _arrow(tester, LogicalKeyboardKey.arrowRight);
    await tester.pump(FocusTooltips.showFor);
    await tester.pumpAndSettle();

    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('clique não deixa balão preso', (tester) async {
    await _pump(tester);

    await _arrow(tester, LogicalKeyboardKey.arrowRight);
    await tester.tap(find.text('Sem balão'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.video_library_outlined));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Biblioteca'), findsNothing);
  });

  testWidgets('desligado (celular) não mostra balão', (tester) async {
    await _pump(tester, enabled: false);

    await _arrow(tester, LogicalKeyboardKey.arrowRight);

    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('balão usa o desenho do app', (tester) async {
    await _pump(tester);
    final theme = Theme.of(tester.element(find.byType(Scaffold))).tooltipTheme;
    final box = theme.decoration! as BoxDecoration;

    expect(box.color, PlayerTheme.tooltipSurface);
    expect(box.border, isNotNull);
    expect(theme.textStyle?.color, PlayerTheme.primaryText);
  });
}
