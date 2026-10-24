import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/hls_resume_probe.dart';
import 'package:player/services/media_player_service.dart';

void main() {
  test('sem motor supervisionado a sonda nao falha', () {
    const player = NoOpMediaPlayerService();
    expect(
      () => logHlsResumeProbe(
        player: player,
        app: player,
        stage: 'switch-position',
        detail: 'skipped=zero',
      ),
      returnsNormally,
    );
  });

  test('etapa sem detalhe tambem e aceita', () {
    const player = NoOpMediaPlayerService();
    expect(
      () => logHlsResumeProbe(player: player, app: player, stage: 'ready'),
      returnsNormally,
    );
  });
}
