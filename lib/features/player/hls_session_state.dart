import 'package:flutter/foundation.dart';

import 'package:player/core/utils/hls_variants.dart';

/// Estado HLS observado pela interface: qualidade escolhida, variante
/// efetivamente aberta e a proteção de posição (um ponto errado não é
/// salvo no histórico). Extraído de player_screen.dart: o controle de
/// reprodução continua na tela, mas os notificadores moram aqui.
class HlsSessionState {
  final ValueNotifier<String> quality =
      ValueNotifier<String>(HlsVariants.autoQualityId);

  /// Rótulo da variante efetivamente aberta (null = master).
  final ValueNotifier<String?> effective = ValueNotifier<String?>(null);

  /// Verdadeiro depois de um pouso incorreto sem correção: a posição
  /// não é gravada até a próxima abertura limpa.
  bool positionProtect = false;

  /// Volta ao estado de uma fonte nova: Automática, sem variante
  /// efetiva e sem proteção.
  void resetForNewSource() {
    quality.value = HlsVariants.autoQualityId;
    effective.value = null;
    positionProtect = false;
  }

  void dispose() {
    quality.dispose();
    effective.dispose();
  }
}
