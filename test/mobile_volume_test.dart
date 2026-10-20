import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/mobile_volume_control.dart';

const _track = MediaTrack(id: 'a1', label: 'Português');

PlaybackSession _session({
  PlaybackStatus status = PlaybackStatus.playing,
  double volume = 0.5,
  bool isMuted = false,
  List<MediaTrack> audio = const [_track],
}) =>
    PlaybackSession(
      status: status,
      volume: volume,
      isMuted: isMuted,
      audioTracks: audio,
    );

Widget _host({
  required Widget child,
  double width = 360,
  double height = 640,
  bool mobile = true,
}) =>
    MaterialApp(
      home: MobileMode(
        enabled: mobile,
        child: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: Center(child: child),
          ),
        ),
      ),
    );

/// Renderiza o controle com a sessao atual do player (como o stream faz no app).
Future<void> _render(
  WidgetTester tester,
  NoOpMediaPlayerService player, {
  ValueChanged<double>? onCommit,
  bool compact = false,
}) =>
    tester.pumpWidget(_host(
      width: compact ? 640 : 360,
      height: compact ? 360 : 640,
      child: MobileVolumeControl(
        player: player,
        session: player.session.copyWith(
          status: PlaybackStatus.playing,
          audioTracks: const [_track],
        ),
        onVolumeCommitted: onCommit,
        compact: compact,
      ),
    ));

void main() {
  group('passo e limites do volume', () {
    test('sobe e desce de 0,05 em 0,05', () {
      expect(steppedVolume(0.5, 1), 0.55);
      expect(steppedVolume(0.55, -1), 0.5);
    });

    test('nao passa de 1,0 nem de 0,0', () {
      expect(steppedVolume(0.98, 1), 1.0);
      expect(steppedVolume(1.0, 1), 1.0);
      expect(steppedVolume(0.02, -1), 0.0);
      expect(steppedVolume(0.0, -1), 0.0);
    });

    test('nao acumula erro de ponto flutuante', () {
      var v = 0.0;
      for (var i = 0; i < 20; i++) {
        v = steppedVolume(v, 1);
      }
      expect(v, 1.0);
      expect(steppedVolume(0.35, 0), closeTo(0.35, 1e-9));
    });
  });

  group('estado do audio', () {
    test('com faixa, disponivel', () {
      expect(mobileAudioState(_session()), MobileAudioState.available);
    });

    test('carregando sem faixa ainda e pendente, nao ausente', () {
      for (final status in [
        PlaybackStatus.idle,
        PlaybackStatus.loading,
        PlaybackStatus.ready,
        PlaybackStatus.buffering,
      ]) {
        expect(
          mobileAudioState(_session(status: status, audio: const [])),
          MobileAudioState.pending,
          reason: status.name,
        );
      }
    });

    test('tocando, pausado ou concluido sem faixa: sem audio', () {
      for (final status in [
        PlaybackStatus.playing,
        PlaybackStatus.paused,
        PlaybackStatus.completed,
      ]) {
        expect(
          mobileAudioState(_session(status: status, audio: const [])),
          MobileAudioState.missing,
          reason: status.name,
        );
      }
    });
  });

  group('controle de volume mobile (widget)', () {
    testWidgets('retrato: mudo, menos, barra e mais, todos com 48 dp',
        (tester) async {
      const player = NoOpMediaPlayerService();
      await _render(tester, player);
      await tester.pumpAndSettle();

      for (final tooltip in [
        'Silenciar',
        'Diminuir volume',
        'Aumentar volume',
      ]) {
        final size = tester.getSize(find.byTooltip(tooltip));
        expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
      }
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paisagem compacta cabe sem estourar', (tester) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(_host(
        width: 640,
        height: 360,
        child: MobileVolumeControl(
          player: player,
          session: _session(),
          compact: true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Aumentar volume'), findsOneWidget);
    });

    testWidgets('mais e menos ajustam o volume e reportam o novo valor',
        (tester) async {
      const player = NoOpMediaPlayerService();
      await player.setVolume(0.5);
      final reported = <double>[];
      await _render(tester, player, onCommit: reported.add);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Aumentar volume'));
      await tester.pumpAndSettle();
      expect(player.session.volume, closeTo(0.55, 1e-9));
      expect(reported.last, closeTo(0.55, 1e-9));

      await _render(tester, player, onCommit: reported.add);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Diminuir volume'));
      await tester.pumpAndSettle();
      expect(player.session.volume, closeTo(0.5, 1e-9));
      expect(reported.last, closeTo(0.5, 1e-9));
    });

    testWidgets('mudo preserva o volume e ajustar desmuta', (tester) async {
      const player = NoOpMediaPlayerService();
      await player.setVolume(0.7);
      await _render(tester, player);
      await tester.pumpAndSettle();

      await player.setMuted(true);
      expect(player.session.isMuted, isTrue);
      expect(player.session.volume, closeTo(0.7, 1e-9));

      await player.setMuted(false);
      expect(player.session.isMuted, isFalse);
      expect(player.session.volume, closeTo(0.7, 1e-9));
    });

    testWidgets('sem faixa de audio: desabilitado e mensagem', (tester) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(_host(
        child: MobileVolumeControl(
          player: player,
          session: _session(audio: const []),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sem áudio nesta mídia'), findsOneWidget);
      for (final button
          in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
      }
    });

    testWidgets('carregando: desabilitado, sem mensagem de ausencia',
        (tester) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(_host(
        child: MobileVolumeControl(
          player: player,
          session: _session(status: PlaybackStatus.loading, audio: const []),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sem áudio nesta mídia'), findsNothing);
      for (final button
          in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
      }
    });

    testWidgets('limite superior: mais nao passa de 100%', (tester) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(_host(
        child: MobileVolumeControl(
          player: player,
          session: _session(volume: 1.0),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Aumentar volume'));
      await tester.pumpAndSettle();
      expect(player.session.volume, 1.0);
    });
  });
}
