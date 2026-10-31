import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/settings/subtitle_appearance_rows.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/preferences_service.dart';

Future<InMemoryPreferencesService> _pump(WidgetTester tester) async {
  final prefs = InMemoryPreferencesService();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AnimatedBuilder(
        animation: prefs,
        builder: (_, __) => ListView(children: subtitleAppearanceRows(prefs)),
      ),
    ),
  ));
  return prefs;
}

void main() {
  testWidgets('escolher uma opcao salva a preferencia', (tester) async {
    final prefs = await _pump(tester);

    await tester.tap(find.text('Branca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amarela').last);
    await tester.pumpAndSettle();
    expect(prefs.current.subtitleColor, SubtitleColor.yellow);

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alta').last);
    await tester.pumpAndSettle();
    expect(prefs.current.subtitlePosition, SubtitlePosition.high);

    await tester.tap(find.text('Médio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grande').last);
    await tester.pumpAndSettle();
    expect(prefs.current.subtitleSize, SubtitleSize.large);
    expect(prefs.current.subtitleColor, SubtitleColor.yellow);
  });

  testWidgets('interruptor desliga o fundo', (tester) async {
    final prefs = await _pump(tester);

    await tester.tap(find.text('Fundo atrás do texto'));
    await tester.pumpAndSettle();
    expect(prefs.current.subtitleBackground, isFalse);
  });
}
