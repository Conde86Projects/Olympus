import 'package:player/models/playback_state.dart';

/// Decide se sair do player grava histórico e posição. Pura, para teste
/// direto: errar aqui apaga o ponto onde a pessoa parou.
///
/// - [position] e [status] vêm do motor no momento de sair.
/// - [savedPosition] é o ponto com que o vídeo abriu.
/// - [sawPosition]: o motor já informou posição acima de zero. Antes
///   disso, o zero é "ainda não chegou ao ponto salvo", não um recuo.
/// - [openedCompleted]: replay de concluído; a base do progresso é zero.
bool shouldSaveProgress({
  required bool rememberPosition,
  required PlaybackStatus status,
  required Duration position,
  required Duration? duration,
  required Duration? savedPosition,
  required bool sawPosition,
  required bool openedCompleted,
}) {
  if (!rememberPosition) return false;
  // Falhou sem nunca ter tocado: não houve visita.
  if (status == PlaybackStatus.error && !sawPosition) return false;
  final base = openedCompleted ? Duration.zero : savedPosition;
  final hadResume = savedPosition != null && savedPosition > Duration.zero;
  final hasProgress = position > Duration.zero ||
      (sawPosition && duration != null && position != base);
  // Sem novidade, não sobrescreve a retomada. Estreia registra a visita.
  return hasProgress || !hadResume;
}
