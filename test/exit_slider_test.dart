import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/widgets/exit_slider.dart';

bool _isFocused(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label))).hasFocus;

/// Foco dentro da subarvore do slider (o Focus interno dele fica
/// ABAIXO do elemento Slider: `Focus.of` de cima nao o alcanca).
bool _sliderFocused(WidgetTester tester) {
  final slider = tester.element(find.byType(Slider));
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  if (identical(focused, slider)) return true;
  var inside = false;
  focused.visitAncestorElements((e) {
    if (identical(e, slider)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> _pumpRow(WidgetTester tester) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          FilledButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Acima')),
          ExitSlider(
            exit: TraversalDirection.down,
            child: Slider(value: 0.5, onChanged: (_) {}),
          ),
          FilledButton(onPressed: () {}, child: const Text('Abaixo')),
        ],
      ),
    ),
  ));
}

/// Foca o slider por travessia direcional (tap nao confere foco a
/// Slider/Button: so campo de texto pede foco no toque).
Future<void> _focusSlider(WidgetTester tester) async {
  await _pumpRow(tester);
  await tester.pumpAndSettle();
  expect(_isFocused(tester, 'Acima'), isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
  expect(_sliderFocused(tester), isTrue);
}

void main() {
  group('ExitSlider (F11)', () {
    testWidgets('Enter sai do slider para o vizinho de baixo',
        (tester) async {
      await _focusSlider(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Abaixo'), isTrue);
      expect(_sliderFocused(tester), isFalse);
    });

    testWidgets('OK (select) sai do slider: controle remoto',
        (tester) async {
      await _focusSlider(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Abaixo'), isTrue);
      expect(_sliderFocused(tester), isFalse);
    });

    testWidgets('Enter fora do slider nao e interceptado',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                  autofocus: true,
                  onPressed: () => pressed++,
                  child: const Text('Acima')),
              ExitSlider(
                exit: TraversalDirection.down,
                child: Slider(value: 0.5, onChanged: (_) {}),
              ),
              FilledButton(onPressed: () {}, child: const Text('Abaixo')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(_isFocused(tester, 'Acima'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pressed, 1);
      expect(_isFocused(tester, 'Acima'), isTrue);
    });
  });
}
