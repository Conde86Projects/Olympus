import 'package:flutter/foundation.dart';

import 'package:player/services/media_player_service.dart';
import 'package:player/services/supervised_player_service.dart';

/// Registra uma etapa da sonda de retomada HLS. Vai para o diagnóstico do
/// motor supervisionado quando existir; em debug também sai no console.
/// Extraído de player_screen.dart sem mudança de comportamento.
///
/// [player] é o motor da chamada; [app] é o motor da aplicação, usado
/// quando [player] não é o supervisionado.
void logHlsResumeProbe({
  required MediaPlayerService player,
  required MediaPlayerService app,
  required String stage,
  String? detail,
}) {
  final inner = player is SupervisedPlayerService
      ? player
      : app is SupervisedPlayerService
          ? app
          : null;
  inner?.logResumeProbe(stage, detail: detail);
  assert(() {
    debugPrint('[hls-resume] $stage ${detail ?? ''}');
    return true;
  }());
}
