import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/player_settings_panel.dart';

const _tracks = [
  MediaTrack(id: 'v1', label: '720p'),
  MediaTrack(id: 'v2', label: '1080p'),
];

Future<void> _pumpPanel(
  WidgetTester tester, {
  PlaybackSession session = const PlaybackSession(),
  PlayerPanelView view = PlayerPanelView.main,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerSettingsPanel(
          player: const NoOpMediaPlayerService(),
          session: session,
          initialView: view,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('sessão de vídeo (spec 13)', () {
    test('copyWith carrega faixas e seleção de vídeo', () {
      const base = PlaybackSession();
      expect(base.videoTracks, isEmpty);
      expect(base.selectedVideoId, isNull);
      final next = base.copyWith(
        videoTracks: _tracks,
        selectedVideoId: () => 'v2',
      );
      expect(next.videoTracks, hasLength(2));
      expect(next.selectedVideoId, 'v2');
      expect(next.copyWith(selectedVideoId: () => null).selectedVideoId,
          isNull);
    });

    test('NoOp selectVideo emite a seleção', () async {
      const player = NoOpMediaPlayerService();
      await player.selectVideo('v2');
      expect(player.session.selectedVideoId, 'v2');
      await player.selectVideo(null);
      expect(player.session.selectedVideoId, isNull);
    });
  });

  group('linha Qualidade no painel', () {
    testWidgets('oculta sem faixas ou com uma só', (tester) async {
      await _pumpPanel(tester);
      expect(find.text('Qualidade'), findsNothing);

      await _pumpPanel(
        tester,
        session: const PlaybackSession(
          videoTracks: [MediaTrack(id: 'v1', label: '720p')],
        ),
      );
      expect(find.text('Qualidade'), findsNothing);
    });

    testWidgets('aparece com múltiplas, valor Automática', (tester) async {
      await _pumpPanel(
        tester,
        session: const PlaybackSession(videoTracks: _tracks),
      );
      expect(find.text('Qualidade'), findsOneWidget);
      expect(find.text('Automática'), findsOneWidget);
    });

    testWidgets('valor mostra o rótulo da faixa ativa', (tester) async {
      await _pumpPanel(
        tester,
        session: const PlaybackSession(
          videoTracks: _tracks,
          selectedVideoId: 'v2',
        ),
      );
      expect(find.text('1080p'), findsOneWidget);
    });

    testWidgets('submenu lista e aplica a escolha', (tester) async {
      const player = NoOpMediaPlayerService();
      await player.selectVideo(null); // ponto de partida conhecido
      await _pumpPanel(
        tester,
        session: const PlaybackSession(videoTracks: _tracks),
      );

      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      expect(find.text('Automática'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);

      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(player.session.selectedVideoId, 'v1');
      // Volta à lista principal sem fechar o painel.
      expect(find.text('Idioma'), findsOneWidget);
    });
  });

  group('legibilidade dos rótulos', () {
    // O _pumpPanel usa o tema claro padrão do MaterialApp (hostil):
    // os rótulos do painel têm cor explícita e nunca herdam do tema,
    // senão um tema claro acima os apagaria no fundo escuro.
    testWidgets('rótulos claros mesmo sob tema claro', (tester) async {
      await _pumpPanel(
        tester,
        session: const PlaybackSession(videoTracks: _tracks),
      );
      for (final label in [
        'Idioma',
        'Legendas',
        'Repetir',
        'Qualidade',
        'Girar',
        'Velocidade de reprodução',
        'Informações do vídeo',
      ]) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.color, PlayerTheme.primaryText,
            reason: label);
      }
    });
  });
}
