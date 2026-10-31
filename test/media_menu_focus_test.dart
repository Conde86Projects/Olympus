import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/models/media_item.dart';
import 'package:player/widgets/media_card.dart';

BoxDecoration _labelDecoration(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('item focado do menu ganha borda; Remover fica vermelho',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaCard(
          item: MediaItem(
            id: 'x',
            title: 'Vídeo menu',
            sourceType: MediaSourceType.url,
            source: 'https://exemplo.com/x.mp4',
            addedAt: DateTime(2026, 1, 1),
          ),
          onTap: () {},
          onToggleFavorite: () {},
          onRemove: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções'));
    await tester.pumpAndSettle();

    // Nenhum item focado no início: a borda aparece depois de navegar.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final remove = _labelDecoration(tester, 'Remover');
    expect(remove.border, isNotNull);
    expect(
      (remove.border! as Border).top.color,
      PlayerTheme.error,
    );
    expect(remove.color, isNotNull);

    // O outro item, sem foco, não tem borda.
    final favorite = _labelDecoration(tester, 'Adicionar aos favoritos');
    expect(favorite.border, isNull);
  });
}
