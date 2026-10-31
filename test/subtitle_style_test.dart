import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/subtitle_style.dart';
import 'package:player/models/preferences.dart';
import 'package:player/widgets/subtitle_overlay.dart';

Future<void> _pump(WidgetTester tester, Size area, List<String> lines,
    {SubtitleStyle style = SubtitleStyle.defaults}) async {
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: area,
        child: SubtitleOverlay(lines: lines, style: style),
      ),
    ),
  ));
}

void main() {
  group('proporcoes do padrao', () {
    const style = SubtitleStyle.defaults;

    test('TV 960x540', () {
      const area = Size(960, 540);
      expect(style.fontSizeFor(area), closeTo(24.3, 0.01));
      expect(style.bottomFor(area), 54);
    });

    test('celular em retrato usa o menor lado', () {
      expect(style.fontSizeFor(const Size(411, 914)), closeTo(18.5, 0.01));
    });

    test('limites de fonte em janela pequena e em tela grande', () {
      expect(style.fontSizeFor(const Size(300, 200)), 16);
      expect(style.fontSizeFor(const Size(3840, 2160)), 40);
    });
  });

  group('escolhas de Ajustes', () {
    test('o padrao das preferencias e o estilo padrao', () {
      final style = SubtitleStyle.fromPreferences(const UserPreferences());
      const area = Size(960, 540);
      expect(style.textColor, SubtitleStyle.defaults.textColor);
      expect(style.backgroundColor, SubtitleStyle.defaults.backgroundColor);
      expect(style.bottomFor(area), SubtitleStyle.defaults.bottomFor(area));
      expect(style.fontSizeFor(area), SubtitleStyle.defaults.fontSizeFor(area));
    });

    test('tamanho, cor, posicao e fundo mudam o estilo', () {
      final style = SubtitleStyle.fromPreferences(const UserPreferences(
        subtitleSize: SubtitleSize.large,
        subtitleColor: SubtitleColor.yellow,
        subtitlePosition: SubtitlePosition.high,
        subtitleBackground: false,
      ));
      const area = Size(960, 540);
      expect(style.textColor, const Color(0xFFFFEB3B));
      expect(style.backgroundColor.a, 0);
      expect(style.bottomFor(area), 108);
      expect(style.fontSizeFor(area), closeTo(31.59, 0.01));
    });

    test('salva e recupera; valor desconhecido cai no padrao', () {
      const prefs = UserPreferences(
        subtitleSize: SubtitleSize.small,
        subtitleColor: SubtitleColor.cyan,
        subtitlePosition: SubtitlePosition.low,
        subtitleBackground: false,
      );
      final back = UserPreferences.fromMap(prefs.toMap());
      expect(back.subtitleSize, SubtitleSize.small);
      expect(back.subtitleColor, SubtitleColor.cyan);
      expect(back.subtitlePosition, SubtitlePosition.low);
      expect(back.subtitleBackground, isFalse);

      final old = UserPreferences.fromMap(const {'subtitleSize': 'gigante'});
      expect(old.subtitleSize, SubtitleSize.medium);
      expect(old.subtitleBackground, isTrue);
    });
  });

  group('SubtitleOverlay', () {
    testWidgets('sobe acima da barra visivel e volta quando ela some',
        (tester) async {
      final inset = ValueNotifier<double>(0);
      addTearDown(inset.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 640,
            height: 360,
            child: SubtitleScope(
              style: SubtitleStyle.defaults,
              bottomInset: inset,
              child: const SubtitleOverlay(lines: ['Legenda']),
            ),
          ),
        ),
      ));
      expect(tester.getRect(find.text('Legenda')).bottom, closeTo(324, 0.01));

      inset.value = 100;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Legenda')).bottom,
          closeTo(360 - 100 - SubtitleOverlay.barGap, 0.01));

      inset.value = 10;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Legenda')).bottom, closeTo(324, 0.01));
    });

    testWidgets('fica acima da base na fracao do estilo', (tester) async {
      await _pump(tester, const Size(640, 360), const ['Legenda']);

      final rect = tester.getRect(find.text('Legenda'));
      expect(rect.bottom, closeTo(360 - 36, 0.01));
      expect(rect.center.dx, closeTo(320, 0.01));
    });

    testWidgets('aplica cor e fundo do estilo', (tester) async {
      const style = SubtitleStyle(
        textColor: Color(0xFFFFFF00),
        backgroundColor: Color(0x00000000),
      );
      await _pump(tester, const Size(960, 540), const ['Legenda'],
          style: style);

      final text = tester.widget<Text>(find.text('Legenda'));
      expect(text.style?.color, const Color(0xFFFFFF00));
      expect(text.style?.backgroundColor, const Color(0x00000000));
    });

    testWidgets('junta as linhas e ignora as vazias', (tester) async {
      await _pump(tester, const Size(960, 540), const [' a ', '', 'b']);

      expect(find.text('a\nb'), findsOneWidget);
    });

    testWidgets('sem texto nao desenha nada', (tester) async {
      await _pump(tester, const Size(960, 540), const ['', '  ']);

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('nao captura toques', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(onTap: () => taps++),
            const SubtitleOverlay(lines: ['Legenda']),
          ],
        ),
      ));

      await tester.tap(find.text('Legenda'), warnIfMissed: false);
      expect(taps, 1);
    });
  });
}
