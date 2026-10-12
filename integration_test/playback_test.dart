import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:player/main.dart' as app;
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_settings_panel.dart';

/// Teste de integracao no Windows real: sobe o app de verdade (mpv nativo)
/// e exercita a matriz de midia da Fase 2.
///
/// Rodar com: `flutter test -d windows integration_test/playback_test.dart`
///
/// Importante: nunca usar `pumpAndSettle` com video em reproducao — o fluxo
/// de posicao reconstrui a tela continuamente e o settle nunca chega. Usar
/// `pump` + sondagem com timeout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reproducao real (mpv)', () {
    testWidgets('app inicia na tela inicial', (tester) async {
      await _launch(tester);
      expect(find.text('Player'), findsWidgets);
    });

    testWidgets('toca MP4 local e a posicao avanca', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample.mp4'));
      await _enableLoop(tester);
      // Posicao sai do zero em ate 20 s.
      final advanced = await _waitForText(tester, RegExp(r'^0:0[1-9]$'),
          timeout: const Duration(seconds: 20));
      expect(advanced, isTrue, reason: 'posição do vídeo avançou');
      // Duracao conhecida do arquivo de teste (~5 s, piso pode variar).
      await _ensureControls(tester);
      final stamps = _timeStamps(tester);
      expect(stamps.length, 2);
      expect(stamps.last, isNot('0:00'), reason: 'duração detectada pelo mpv');
      await _goHome(tester);
    });

    testWidgets('video sem controles embutidos duplicados', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample.mp4'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      // O default do Video e AdaptiveVideoControls: se alguem remover o
      // NoVideoControls do servico, a barra embutida reaparece atras da
      // nossa (duas barras sobrepostas).
      final videos = tester.widgetList<Video>(find.byType(Video));
      expect(videos, isNotEmpty, reason: 'superfície de vídeo presente');
      for (final video in videos) {
        expect(video.controls, isNull,
            reason: 'controles embutidos do media_kit_video desligados');
      }
      await _goHome(tester);
    });

    testWidgets('Girar gira o video em quartos de volta', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample.mp4'));
      await _enableLoop(tester);
      await _ensureControls(tester);
      int turns() =>
          tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns;
      expect(turns(), 0);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('Girar horário'));
      await tester.pump();
      expect(turns(), 1);
      await tester.tap(find.byTooltip('Girar horário'));
      await tester.pump();
      expect(turns(), 2);
      await tester.tap(find.byTooltip('Girar anti-horário'));
      await tester.pump();
      expect(turns(), 1);
      // Os botoes agem sem sair do painel.
      expect(find.text('Velocidade de reprodução'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _goHome(tester);
    });

    testWidgets('painel abre ancorado acima da engrenagem', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample.mp4'));
      await _ensureControls(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final panel = tester.getRect(find.byType(PlayerSettingsPanel));
      final gear = tester.getRect(find.byTooltip('Configurações'));
      // Painel acima do botao, com a seta de 10 px entre eles.
      expect(panel.bottom, lessThanOrEqualTo(gear.top + 1));
      expect(panel.bottom, greaterThanOrEqualTo(gear.top - 14));
      // Centralizado no icone clicado.
      expect((panel.center.dx - gear.center.dx).abs(), lessThan(2));
      await tester.tap(find.text('Fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _goHome(tester);
    });

    testWidgets('pausa congela a posicao', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample.mp4'));
      await _enableLoop(tester);
      // Pausa no meio do video, longe do ponto de repeticao.
      final mid = await _waitForText(tester, RegExp(r'^0:0[2-4]$'),
          timeout: const Duration(seconds: 25));
      expect(mid, isTrue);

      await tester.tap(find.byTooltip('Pausar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('Reproduzir'), findsOneWidget);
      await _ensureControls(tester);
      final frozen = _positionText(tester);
      expect(frozen, isNotNull);

      await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
      await tester.pump();
      await _ensureControls(tester);
      expect(_positionText(tester), frozen,
          reason: 'posição congelada durante a pausa');

      await tester.tap(find.byTooltip('Reproduzir'));
      await tester.pump();
      await _goHome(tester);
    });

    testWidgets('lista duas faixas de audio no MKV', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample_multi_audio.mkv'));
      // Repeticao ligada para o arquivo de 5 s nao terminar (mpv limpa
      // as faixas ao ejetar no fim) antes da verificacao.
      await _enableLoop(tester);
      // Faixas chegam em tempo real; aguarda antes de abrir o painel.
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
      await tester.pump();
      await _ensureControls(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Idioma'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Inglês'), findsOneWidget);
      expect(find.text('Comentários'), findsOneWidget);
      await tester.tap(find.text('Comentários'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Voltou a lista principal sem fechar o painel.
      expect(find.text('Velocidade de reprodução'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _goHome(tester);
    });

    testWidgets('encontra a legenda externa do MP4', (tester) async {
      await _launch(tester);
      // sample.srt tem o mesmo basename: o mpv carrega sozinho.
      await _openFile(tester, await _assetPath('sample.mp4'));
      await _enableLoop(tester);
      // Legenda externa carrega em tempo real; aguarda antes do painel.
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
      await tester.pump();
      await _ensureControls(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Legendas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nenhuma legenda disponível'), findsNothing);
      expect(find.text('Desativadas'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _goHome(tester);
    });

    testWidgets('arquivo incompativel mostra erro', (tester) async {
      await _launch(tester);
      final temp = await Directory.systemTemp.createTemp('player_broken_');
      final broken = File('${temp.path}/quebrado.mp4');
      await broken.writeAsBytes(List<int>.generate(256, (i) => i % 251));
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      await _openFile(tester, broken.path);
      final errored = await _waitForText(tester, 'Não foi possível reproduzir',
          timeout: const Duration(seconds: 20));
      expect(errored, isTrue, reason: 'erro de mídia exibido');
      await _goHome(tester);
    });

    testWidgets('toca video ultrawide 21:9', (tester) async {
      await _launch(tester);
      await _openFile(tester, await _assetPath('sample_21x9.mp4'));
      await _enableLoop(tester);
      final advanced = await _waitForText(tester, RegExp(r'^0:0[1-9]$'),
          timeout: const Duration(seconds: 20));
      expect(advanced, isTrue, reason: 'posição do 21:9 avançou');
      await _goHome(tester);
    });
  });
}

/// Sobe o app de verdade em cada teste: o integration_test reinicia o
/// binding entre testes, entao cada caso precisa do proprio `main()`.
Future<void> _launch(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();
  // Primeira execucao mostra a apresentacao inicial; dispensa quando ela
  // aparece para os testes partirem sempre da tela inicial.
  if (find.text('Começar').evaluate().isNotEmpty) {
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
  }
}

/// Localiza um arquivo de `test_assets/` subindo a partir do diretorio atual.
Future<String> _assetPath(String name) async {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/test_assets/$name');
    if (await candidate.exists()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError(
      'test_assets/$name não encontrado a partir de ${Directory.current.path}');
}

/// Abre um arquivo pela UI: tela inicial -> abrir -> caminho -> player.
Future<void> _openFile(WidgetTester tester, String path) async {
  await tester.tap(find.widgetWithText(FocusableButton, 'Abrir arquivo'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, path);
  await tester.tap(find.widgetWithText(FocusableButton, 'Abrir arquivo'));
  // Player abre; sem settle (reproducao continua).
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

/// Ativa repeticao do item para os videos curtos de 5 s nao terminarem
/// no meio da verificacao.
Future<void> _enableLoop(WidgetTester tester) async {
  await _ensureControls(tester);
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Repetir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Repetir item'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Fechar'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Mostra os controles pela tecla M (mesmo `_poke` do toque no video;
/// o mudo nao afeta nenhuma assercao). Toques por coordenada (`tapAt`)
/// se mostraram nao confiaveis no Windows real, entao o teclado e o
/// caminho deterministico aqui.
Future<void> _poke(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Garante controles visiveis, repetindo o toque ate aparecerem.
Future<void> _ensureControls(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    if (find.byTooltip('Configurações').evaluate().isNotEmpty) return;
    await _poke(tester);
  }
  throw StateError('controles do player não apareceram');
}

/// Volta a tela inicial pelo voltar da AppBar.
Future<void> _goHome(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

/// Sonda ate um texto aparecer, em tempo real de parede (o mpv avanca no
/// relogio real). Reexibe os controles a cada passada.
Future<bool> _waitForText(
  WidgetTester tester,
  Pattern pattern, {
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future.delayed(
          const Duration(milliseconds: 500),
        ));
    await tester.pump();
    await _poke(tester);
    final matches = tester.widgetList(find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.data != null &&
        (pattern is RegExp
            ? pattern.hasMatch(widget.data!)
            : widget.data!.contains(pattern))));
    if (matches.isNotEmpty) return true;
  }
  return false;
}

/// Rotulos temporais da barra (atual, duracao).
List<String> _timeStamps(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byWidgetPredicate((widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'^\d{1,2}:\d{2}$').hasMatch(widget.data!)))
      .map((t) => t.data!)
      .toList();
}

/// Texto do tempo atual (primeiro rotulo temporal da barra).
String? _positionText(WidgetTester tester) {
  final stamps = _timeStamps(tester);
  return stamps.isEmpty ? null : stamps.first;
}
