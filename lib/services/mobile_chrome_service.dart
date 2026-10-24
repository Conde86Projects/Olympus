import 'package:flutter/foundation.dart';

/// Chrome mobile: o que o aparelho mostra e esconde em volta do video.
/// Dono do estado (cheia); a tela apenas assina via [Listenable].
abstract class MobileChromeService extends ChangeNotifier {
  /// Cheia ativa ou nao. Valor inicial sincrono: desligada.
  bool get isFullscreen;

  /// Liga/desliga a cheia (imersao + orientacao no adaptador real).
  /// Chamada repetida com o mesmo valor nao renotifica.
  Future<void> setFullscreen(bool enabled);
}
