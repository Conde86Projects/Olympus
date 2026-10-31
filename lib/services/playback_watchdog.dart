import 'dart:async';

import 'package:player/models/playback_state.dart';

/// Vigia dos prazos de reproducao (spec 26): acusa carga travada, buffer
/// continuo e "tocando" parado no zero (rede caiu antes do primeiro quadro,
/// sem buffering para o prazo de buffer pegar). Cada prazo dispara uma vez
/// e so se a sessao ainda estiver no mesmo estado.
class PlaybackWatchdog {
  PlaybackWatchdog({
    required this.loadTimeout,
    required this.bufferTimeout,
    required this.current,
    required this.onExpired,
  });

  final Duration loadTimeout;
  final Duration bufferTimeout;

  /// Sessao vista pela tela, consultada quando um prazo vence.
  final PlaybackSession Function() current;

  /// Recebe o nome do evento para o log tecnico.
  final void Function(String event) onExpired;

  Timer? _load;
  Timer? _buffer;
  Timer? _start;

  /// Abertura aceita pelo motor: comeca a contar a carga.
  void armLoad() {
    _load?.cancel();
    _load = Timer(loadTimeout, () {
      if (current().status != PlaybackStatus.loading) return;
      onExpired('timeout-load');
    });
  }

  /// Ajusta os prazos a cada nova sessao.
  void observe(PlaybackSession session) {
    final status = session.status;
    if (status != PlaybackStatus.loading) _load?.cancel();

    if (status != PlaybackStatus.buffering) {
      _buffer?.cancel();
      _buffer = null;
    } else {
      _buffer ??= Timer(bufferTimeout, () {
        _buffer = null;
        if (current().status != PlaybackStatus.buffering) return;
        onExpired('timeout-buffer');
      });
    }

    if (!isStalledAtStart(session)) {
      _start?.cancel();
      _start = null;
    } else {
      _start ??= Timer(loadTimeout, () {
        _start = null;
        if (!isStalledAtStart(current())) return;
        onExpired('timeout-start');
      });
    }
  }

  void cancel() {
    _load?.cancel();
    _load = null;
    _buffer?.cancel();
    _buffer = null;
    _start?.cancel();
    _start = null;
  }

  static bool isStalledAtStart(PlaybackSession session) =>
      session.status == PlaybackStatus.playing &&
      session.position <= Duration.zero;
}
