import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/playback_state.dart';

/// Resultado de um tick do observador de qualidade HLS (função pura).
enum HlsObserverOutcome {
  /// Não está tocando: a janela é descartada.
  notPlaying,

  /// Janela nova aberta agora: só mede nos próximos ticks.
  started,

  /// Janela ainda curta (menos de 3 s de parede): nada a decidir.
  waiting,

  /// Medição impossível (relógio sem avanço): janela descartada.
  unmeasurable,

  /// Reprodução acompanha o tempo real: observação encerra.
  healthy,

  /// Reprodução atrasa: a tela decide se desce um degrau.
  slow,
}

/// Próximo estado do observador e o que a tela deve fazer.
class HlsObserverStep {
  const HlsObserverStep(
    this.outcome, {
    this.startAt,
    this.startPosition,
    this.ratio,
  });

  final HlsObserverOutcome outcome;

  /// Início da janela a guardar (null = descartar).
  final DateTime? startAt;
  final Duration? startPosition;

  /// Razão tempo reproduzido / tempo real (healthy e slow).
  final double? ratio;
}

/// Um tick do observador: decide a partir do estado atual, sem efeitos.
/// Extraído de player_screen.dart; a tela guarda a janela devolvida e
/// executa o efeito de cada resultado.
HlsObserverStep stepHlsObserver({
  required PlaybackStatus status,
  required Duration position,
  required DateTime now,
  DateTime? startAt,
  Duration? startPosition,
}) {
  if (status != PlaybackStatus.playing) {
    return const HlsObserverStep(HlsObserverOutcome.notPlaying);
  }
  if (startAt == null || startPosition == null) {
    return HlsObserverStep(
      HlsObserverOutcome.started,
      startAt: now,
      startPosition: position,
    );
  }
  final wall = now.difference(startAt);
  if (wall < const Duration(seconds: 3)) {
    return HlsObserverStep(
      HlsObserverOutcome.waiting,
      startAt: startAt,
      startPosition: startPosition,
    );
  }
  final ratio = HlsVariants.playbackRatio(startPosition, position, wall);
  if (ratio == null) {
    return const HlsObserverStep(HlsObserverOutcome.unmeasurable);
  }
  if (ratio >= HlsVariants.observedRatioThreshold) {
    return HlsObserverStep(HlsObserverOutcome.healthy, ratio: ratio);
  }
  return HlsObserverStep(HlsObserverOutcome.slow, ratio: ratio);
}
