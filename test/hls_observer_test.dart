import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/hls_observer.dart';
import 'package:player/models/playback_state.dart';

final _t0 = DateTime(2026, 10, 24, 12);

void main() {
  test('fora de reproducao descarta a janela', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.paused,
      position: const Duration(seconds: 5),
      now: _t0,
      startAt: _t0,
      startPosition: Duration.zero,
    );
    expect(step.outcome, HlsObserverOutcome.notPlaying);
    expect(step.startAt, isNull);
    expect(step.startPosition, isNull);
  });

  test('primeiro tick tocando abre a janela', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.playing,
      position: const Duration(seconds: 2),
      now: _t0,
    );
    expect(step.outcome, HlsObserverOutcome.started);
    expect(step.startAt, _t0);
    expect(step.startPosition, const Duration(seconds: 2));
  });

  test('janela com menos de 3 s espera e mantem o inicio', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.playing,
      position: const Duration(seconds: 2),
      now: _t0.add(const Duration(seconds: 2)),
      startAt: _t0,
      startPosition: Duration.zero,
    );
    expect(step.outcome, HlsObserverOutcome.waiting);
    expect(step.startAt, _t0);
  });

  test('reproducao no tempo real (ratio 1) e saudavel', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.playing,
      position: const Duration(seconds: 5),
      now: _t0.add(const Duration(seconds: 5)),
      startAt: _t0,
      startPosition: Duration.zero,
    );
    expect(step.outcome, HlsObserverOutcome.healthy);
    expect(step.ratio, closeTo(1.0, 1e-9));
  });

  test('reproducao atrasada (ratio 0,5) e lenta', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.playing,
      position: const Duration(milliseconds: 2500),
      now: _t0.add(const Duration(seconds: 5)),
      startAt: _t0,
      startPosition: Duration.zero,
    );
    expect(step.outcome, HlsObserverOutcome.slow);
    expect(step.ratio, closeTo(0.5, 1e-9));
  });

  test('relogio sem avanco nao mede', () {
    final step = stepHlsObserver(
      status: PlaybackStatus.playing,
      position: const Duration(seconds: 5),
      now: _t0,
      startAt: _t0,
      startPosition: Duration.zero,
    );
    // Sem tempo de parede, nao ha como medir: wall < 3 s cai em waiting.
    expect(step.outcome, HlsObserverOutcome.waiting);
  });
}
