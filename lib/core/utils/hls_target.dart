import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/playback_state.dart';

/// Regras puras de reproducao HLS usadas pelo player (extraidas de
/// player_screen.dart, sem mudanca de comportamento).

/// A fonte e uma playlist HLS (.m3u8), pelo caminho da URL.
bool isM3u8Url(String source) {
  final uri = Uri.tryParse(source);
  return uri != null && uri.path.toLowerCase().endsWith('.m3u8');
}

/// Carregando ou em buffer: a sonda de retomada espera esses estados.
bool isLoadingStatus(PlaybackStatus status) =>
    status == PlaybackStatus.loading || status == PlaybackStatus.buffering;

/// URL concreta de uma selecao HLS: Original (master), variante validada
/// contra as reais, ou Automatica (teto calculado pela [decision]). Variante
/// que sumiu do master cai na Automatica.
String hlsTargetFor(
  String qualityId,
  String master,
  List<HlsVariant> variants,
  HlsAutoDecision decision,
) {
  if (qualityId == HlsVariants.originalQualityId) return master;
  if (qualityId != HlsVariants.autoQualityId) {
    for (final variant in variants) {
      if (variant.uri.toString() == qualityId) return qualityId;
    }
  }
  return HlsVariants.automaticUrl(
    master,
    variants,
    capped: decision.capped,
    maxHeight: decision.maxHeight,
    maxBandwidth: decision.maxBandwidth,
  );
}
