import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/player_controls.dart';

void main() {
  testWidgets('trilho de volume do desktop avisa o volume escolhido',
      (tester) async {
    const player = NoOpMediaPlayerService();
    final reported = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 300,
          child: PlayerControls(
            player: player,
            session: player.session.copyWith(
              status: PlaybackStatus.playing,
              duration: () => const Duration(minutes: 10),
            ),
            onOpenSettings: (_) {},
            onVolumeCommitted: reported.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final volumeSlider = tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere((s) => s.max == 1.0);
    volumeSlider.onChanged!(0.3);
    await tester.pumpAndSettle();

    expect(reported, [0.3]);
    expect(player.session.volume, closeTo(0.3, 1e-9));
  });
}
