import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/player_volume_policy.dart';
import 'package:player/services/media_player_service.dart';

void main() {
  // O NoOp guarda o estado no motor: cada teste parte do volume que define.
  const player = NoOpMediaPlayerService();

  group('PlayerVolumePolicy', () {
    test('passo para cima aplica no motor e salva como inicial', () async {
      await player.setVolume(0.5);
      final saved = <double>[];
      final policy = PlayerVolumePolicy(
        player: player,
        currentVolume: () => player.session.volume,
        savePreference: saved.add,
      );

      await policy.step(1);

      expect(player.session.volume, closeTo(0.55, 1e-9));
      expect(saved, [closeTo(0.55, 1e-9)]);
    });

    test('passo para baixo a partir do volume da sessao', () async {
      await player.setVolume(0.5);
      final policy = PlayerVolumePolicy(
        player: player,
        currentVolume: () => player.session.volume,
        savePreference: (_) {},
      );

      await policy.step(-1);

      expect(player.session.volume, closeTo(0.45, 1e-9));
    });

    test('passos rapidos partem do alvo pendente, nao da sessao atrasada',
        () async {
      await player.setVolume(0.5);
      final saved = <double>[];
      final policy = PlayerVolumePolicy(
        player: player,
        // A sessao ainda mostra 0,5 mesmo depois do primeiro passo.
        currentVolume: () => 0.5,
        savePreference: saved.add,
      );

      final first = policy.step(1);
      final second = policy.step(1);
      await Future.wait([first, second]);

      expect(player.session.volume, closeTo(0.6, 1e-9));
      expect(saved.last, closeTo(0.6, 1e-9));
    });

    test('limita entre 0,0 e 1,0', () async {
      await player.setVolume(1.0);
      final policy = PlayerVolumePolicy(
        player: player,
        currentVolume: () => player.session.volume,
        savePreference: (_) {},
      );

      await policy.step(1);
      expect(player.session.volume, 1.0);

      await player.setVolume(0.0);
      await policy.step(-1);
      expect(player.session.volume, 0.0);
    });

    test('persist salva sem tocar no motor', () async {
      await player.setVolume(0.3);
      final saved = <double>[];
      final policy = PlayerVolumePolicy(
        player: player,
        currentVolume: () => player.session.volume,
        savePreference: saved.add,
      );

      await policy.persist(0.8);

      expect(saved, [0.8]);
      expect(player.session.volume, closeTo(0.3, 1e-9));
    });
  });
}
