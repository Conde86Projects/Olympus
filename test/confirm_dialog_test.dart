import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/widgets/confirm_dialog.dart';

/// Regressão (TV, D-pad): o diálogo de confirmação nasce com o foco
/// no Cancelar (padrão seguro §26.6) e o OK imediato cancela em vez
/// de destruir. Cobre o relato "cliquei remover e nada aconteceu":
/// o foco real estava no Cancelar enquanto o Remover preenchido
/// parecia ativo.
void main() {
  Future<bool?> openDialog(WidgetTester tester) {
    return confirmDestructiveAction(
      tester.element(find.text('Abrir')),
      title: 'Remover da biblioteca?',
      message: "'Curto' sai da biblioteca e do histórico.",
    );
  }

  Widget app() => const MaterialApp(
        home: Scaffold(body: Text('Abrir')),
      );

  testWidgets('OK imediato no D-pad cancela (foco nasce no Cancelar)',
      (tester) async {
    await tester.pumpWidget(app());
    final future = openDialog(tester);
    await tester.pumpAndSettle();

    // O diálogo está vivo e responde ao D-pad: Enter sem navegar
    // ativa o Cancelar focado.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(await future, isFalse);
  });

  testWidgets('toque explicito no Remover confirma', (tester) async {
    await tester.pumpWidget(app());
    final future = openDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();

    expect(await future, isTrue);
  });
}
