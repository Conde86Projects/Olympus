import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/last_seen.dart';
import 'package:player/models/media_item.dart';
import 'package:player/widgets/media_card.dart';

MediaItem _item({DateTime? lastPlayedAt}) => MediaItem(
      id: 'x',
      title: 'Vídeo data',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/x.mp4',
      addedAt: DateTime(2026, 1, 1),
      lastPlayedAt: lastPlayedAt,
    );

void main() {
  final now = DateTime(2026, 5, 20, 0, 30);

  group('texto do ultimo acesso', () {
    test('hoje', () {
      expect(lastSeenLabel(DateTime(2026, 5, 20, 0, 5), now), 'Visto hoje');
    });
    test('ontem segue o dia do calendario, nao 24 horas', () {
      // 23h50 do dia anterior: so 40 minutos antes, mas e "ontem".
      expect(lastSeenLabel(DateTime(2026, 5, 19, 23, 50), now), 'Visto ontem');
    });
    test('tres dias atras mostra dia e mes', () {
      expect(lastSeenLabel(DateTime(2026, 5, 17, 10), now),
          'Visto em 17 de mai.');
    });
    test('ano passado inclui o ano', () {
      expect(lastSeenLabel(DateTime(2025, 12, 3, 10), now),
          'Visto em 3 de dez. de 2025');
    });
    test('nunca tocou nao tem texto', () {
      expect(lastSeenLabel(null, now), isNull);
    });
  });

  group('cartao', () {
    Future<void> pump(WidgetTester tester, MediaItem item) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MediaCard(item: item, now: now)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra a linha quando ja tocou', (tester) async {
      await pump(tester, _item(lastPlayedAt: DateTime(2026, 5, 19, 22)));
      expect(find.text('Visto ontem'), findsOneWidget);
    });

    testWidgets('nao estoura na janela compacta com texto maior',
        (tester) async {
      tester.view.physicalSize = const Size(480, 270);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: MediaCard(
            item: _item(lastPlayedAt: DateTime(2025, 12, 3)),
            now: now,
            onToggleFavorite: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Visto em 3 de dez. de 2025'), findsOneWidget);
    });

    testWidgets('esconde a linha quando nunca tocou', (tester) async {
      await pump(tester, _item());
      expect(find.textContaining('Visto'), findsNothing);
    });
  });
}
