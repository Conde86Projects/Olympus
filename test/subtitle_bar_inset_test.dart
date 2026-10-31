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

void main() {
  testWidgets('barra visivel: mede do topo dela ate a base do video',
      (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    addTearDown(subject.dispose);
    await _pump(tester, subject);

    subject.schedule();
    await tester.pump();
    expect(subject.inset.value, 110);
  });

  testWidgets('barra oculta conta como zero', (tester) async {
    var visible = true;
    final subject = SubtitleBarInset(barVisible: () => visible);
    addTearDown(subject.dispose);
    await _pump(tester, subject);
    subject.schedule();
    await tester.pump();

    visible = false;
    subject.schedule();
    await tester.pump();
    expect(subject.inset.value, 0);
  });

  testWidgets('sem barra montada conta como zero', (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    addTearDown(subject.dispose);
    await _pump(tester, subject, withBar: false);

    subject.schedule();
    await tester.pump();
    expect(subject.inset.value, 0);
  });

  testWidgets('medida pendente nao falha depois do dispose', (tester) async {
    final subject = SubtitleBarInset(barVisible: () => true);
    await _pump(tester, subject);

    subject.schedule();
    subject.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
