import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/widgets/exit_slider.dart';

Widget _host({required bool tv, required ValueNotifier<double> value}) =>
    MaterialApp(
      home: TvMode(
        enabled: tv,
        child: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: value,
                builder: (context, v, _) => ExitSlider(
                  exit: TraversalDirection.down,
                  child: Slider(
                    autofocus: true,
                    value: v,
                    onChanged: (n) => value.value = n,
                  ),
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Pausar')),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('TV: seta para baixo sai do trilho sem mover o video',
      (tester) async {
    final value = ValueNotifier(0.5);
    await tester.pumpWidget(_host(tv: true, value: value));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(value.value, 0.5);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<TextButton>(),
      isNotNull,
      reason: 'o foco deve ir para o botao abaixo do trilho',
    );
  });

  testWidgets('TV: esquerda e direita continuam movendo o trilho',
      (tester) async {
    final value = ValueNotifier(0.5);
    await tester.pumpWidget(_host(tv: true, value: value));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value.value, greaterThan(0.5));
  });

  testWidgets('desktop: comportamento do trilho nao muda', (tester) async {
    final value = ValueNotifier(0.5);
    await tester.pumpWidget(_host(tv: false, value: value));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(value.value, lessThan(0.5));
  });
}
