import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/widgets/app_toast.dart';

/// Aviso do app (toast): cartão no topo, centralizado e com largura
/// limitada, com ícone. Cai do topo, fica alguns segundos e sobe. Antes
/// era a faixa padrão do SnackBar, na largura toda colada no rodapé.
Future<void> _show(WidgetTester tester, Size size, {bool error = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showAppToast(
                context, 'Catálogo atualizado: 1 item.',
                error: error),
            child: const Text('mostrar'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('mostrar'));
  await tester.pump();
}

Rect _card(WidgetTester tester) =>
    tester.getRect(find.byKey(AppToast.cardKey));

/// Ate o aviso sumir (queda + permanencia + subida), sem timer pendente.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(AppToast.drop);
  await tester.pump(AppToast.hold);
  await tester.pump(AppToast.lift + const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  for (final size in const [Size(1280, 720), Size(390, 844), Size(960, 540)]) {
    testWidgets('no topo, centralizado e limitado em $size', (tester) async {
      await _show(tester, size);
      await tester.pump(AppToast.drop);
      final rect = _card(tester);
      expect(rect.width, lessThanOrEqualTo(AppToast.maxWidth));
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(size.width - 16));
      expect((rect.center.dx - size.width / 2).abs(), lessThan(1));
      // No topo, solto da borda.
      expect(rect.top, greaterThanOrEqualTo(16));
      expect(rect.bottom, lessThan(size.height / 3));
      expect(find.text('Catálogo atualizado: 1 item.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      // Nada de SnackBar no rodapé.
      expect(find.byType(SnackBar), findsNothing);
      await _finish(tester);
    });
  }

  testWidgets('cai do topo, espera e sobe', (tester) async {
    await _show(tester, const Size(1280, 720));
    final card = find.descendant(
        of: find.byKey(AppToast.cardKey), matching: find.byType(Material));

    // Começa acima do lugar e desce.
    final start = tester.getRect(card).top;
    await tester.pump(); // primeiro quadro: a animação começa a contar
    await tester.pump(AppToast.drop);
    final placed = tester.getRect(card).top;
    expect(start, lessThan(placed));

    // Fica parado durante a permanência.
    // Quadros de 100 ms (como na tela real, sempre desenhando).
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.getRect(card).top, placed);

    // Depois sobe (quadros de 50 ms, margem de 3 s).
    var rose = false;
    for (var i = 0; i < 60 && !rose; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      rose = card.evaluate().isNotEmpty &&
          tester.getRect(card).top < placed;
    }
    expect(rose, isTrue);
    await tester.pump(AppToast.lift);
    await tester.pump();
    expect(find.text('Catálogo atualizado: 1 item.'), findsNothing);
  });

  testWidgets('não bloqueia toques no app', (tester) async {
    var taps = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: TextButton(
              onPressed: () {
                taps++;
                showAppToast(context, 'Aviso');
              },
              child: const Text('topo'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('topo'));
    await tester.pump(AppToast.drop);
    await tester.tap(find.text('topo'), warnIfMissed: false);
    expect(taps, 2);
    await _finish(tester);
  });

  testWidgets('erro usa o ícone de erro', (tester) async {
    await _show(tester, const Size(1280, 720), error: true);
    await tester.pump(AppToast.drop);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('um novo aviso substitui o anterior', (tester) async {
    await _show(tester, const Size(1280, 720));
    await tester.pump(AppToast.drop);
    await tester.tap(find.text('mostrar'));
    await tester.pump(AppToast.drop);
    expect(find.text('Catálogo atualizado: 1 item.'), findsOneWidget);
    await _finish(tester);
  });
}
