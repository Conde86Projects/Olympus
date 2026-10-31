import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/widgets/focusable_button.dart';

void main() {
  testWidgets('foco e destacado em azul; destrutivo fica vermelho',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          FocusableButton(label: 'Cancelar', autofocus: true, onPressed: () {}),
          FocusableButton(
            label: 'Remover',
            destructive: true,
            onPressed: () {},
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final buttons =
        tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
    final cancel = buttons[0].style!;
    final remove = buttons[1].style!;
    const focused = {WidgetState.focused};

    expect(cancel.side!.resolve(focused)!.color, PlayerTheme.accent);
    expect(cancel.side!.resolve(focused)!.width, 2);
    expect(remove.side!.resolve(focused)!.color, PlayerTheme.error);
    // Sem foco: nenhum dos dois tem a borda de destaque.
    expect(cancel.side!.resolve(const {})!.width, isNot(2));
    expect(remove.side!.resolve(const {})!.width, isNot(2));
  });
}
