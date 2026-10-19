import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/media_item.dart';
import 'package:player/widgets/media_card.dart';

const _plain = Color(0xFF1C1C1E);

MediaItem _item() => MediaItem(
      id: 'x',
      title: 'Vídeo foco',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/x.mp4',
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('destaque do cartao de midia', () {
    testWidgets('cartao focado pinta o cartao inteiro com o azul de foco',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCard(item: _item(), onTap: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      // Tab leva o foco ao corpo do cartao (primeiro focavel).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final card = tester.widget<Card>(find.byType(Card).first);
      expect(
        card.color,
        Color.alphaBlend(PlayerTheme.accent.withValues(alpha: 0.25), _plain),
      );
    });

    testWidgets('cartao sem foco fica na cor de repouso', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCard(item: _item(), onTap: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      final card = tester.widget<Card>(find.byType(Card).first);
      expect(card.color, _plain);
    });
  });

  group('estado do add-on', () {
    testWidgets('ativo usa o verde; inativo mantem a cor do texto',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      expect(addonStateColor(context, AddonState.active), PlayerTheme.success);
      expect(addonStateColor(context, AddonState.inactive), isNull);
    });
  });
}
