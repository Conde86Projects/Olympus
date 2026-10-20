import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/core/utils/volume_step.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/player_controls.dart';

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

  testWidgets('celular: so o icone de mudo, sem barra nem + e -',
      (tester) async {
    const player = NoOpMediaPlayerService();
    await tester.pumpWidget(MaterialApp(
      home: MobileMode(
        enabled: true,
        child: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PlayerControls(
              player: player,
              session: player.session.copyWith(
                status: PlaybackStatus.playing,
                duration: () => const Duration(minutes: 10),
                audioTracks: const [MediaTrack(id: 'a1', label: 'Pt')],
              ),
              onOpenSettings: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Silenciar'), findsOneWidget);
    expect(find.byTooltip('Aumentar volume'), findsNothing);
    expect(find.byTooltip('Diminuir volume'), findsNothing);
    final volumeSliders = tester
        .widgetList<Slider>(find.byType(Slider))
        .where((s) => s.max == 1.0);
    expect(volumeSliders, isEmpty);
  });
}
