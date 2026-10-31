import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/subtitle_bar_inset.dart';

Future<void> _pump(WidgetTester tester, SubtitleBarInset subject,
    {bool withBar = true}) async {
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 640,
        height: 360,
        child: Stack(
          children: [
            Positioned.fill(child: SizedBox(key: subject.areaKey)),
            if (withBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                height: 100,
                child: SizedBox(key: subject.barKey),
              ),
          ],
        ),
      ),
    ),
  ));
}

/// A medida sai no fim de um quadro; a tela real sempre tem um a caminho.
Future<void> _measure(WidgetTester tester, SubtitleBarInset subject) async {
  subject.schedule();
  tester.binding.scheduleFrame();
  await tester.pump();
}

void main() {
  testWidgets('barra visivel: mede do topo dela ate a base do video',
      (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    addTearDown(subject.dispose);
    await _pump(tester, subject);

    await _measure(tester, subject);
    expect(subject.inset.value, 110);
  });

  testWidgets('barra oculta conta como zero', (tester) async {
    var visible = true;
    final subject = SubtitleBarInset(barVisible: () => visible);
    addTearDown(subject.dispose);
    await _pump(tester, subject);
    await _measure(tester, subject);
    expect(subject.inset.value, 110);

    visible = false;
    await _measure(tester, subject);
    expect(subject.inset.value, 0);
  });

  testWidgets('sem barra montada conta como zero', (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    addTearDown(subject.dispose);
    await _pump(tester, subject, withBar: false);

    await _measure(tester, subject);
    expect(subject.inset.value, 0);
  });

  testWidgets('medida pendente nao falha depois do dispose', (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    await _pump(tester, subject);

    subject.schedule();
    subject.dispose();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
