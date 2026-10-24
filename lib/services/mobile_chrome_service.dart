import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Chrome mobile: o que o aparelho mostra e esconde em volta do video.
/// Dono do estado (cheia); a tela apenas assina via [Listenable].
abstract class MobileChromeService extends ChangeNotifier {
  /// Cheia ativa ou nao. Valor inicial sincrono: desligada.
  bool get isFullscreen;

  /// Liga/desliga a cheia (imersao + orientacao no adaptador real).
  /// Chamada repetida com o mesmo valor nao renotifica.
  Future<void> setFullscreen(bool enabled);
}

/// Adaptador real (mobile): imersao + paisagem via `SystemChrome`.
///
/// Extracao fiel de `_applyMobileFullscreen` do player screen:
/// mesma ordem de chamadas, mesmos parametros
/// (`immersiveSticky` + paisagem na entrada; `edgeToEdge` + `const []`
/// na saida).
class SystemMobileChrome extends MobileChromeService {
  bool _fullscreen = false;

  @override
  bool get isFullscreen => _fullscreen;

  @override
  Future<void> setFullscreen(bool enabled) async {
    if (enabled == _fullscreen) return;
    // Estado só comita após as chamadas com sucesso (antes, o campo da
    // tela também só era escrito depois): canal falhou, sem cheia.
    await SystemChrome.setEnabledSystemUIMode(enabled
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(enabled
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const []);
    _fullscreen = enabled;
    notifyListeners();
  }
}

/// Variante neutra para desktop/testes sem mobile: ignora os pedidos.
class NoOpMobileChrome extends MobileChromeService {
  @override
  bool get isFullscreen => false;

  @override
  Future<void> setFullscreen(bool enabled) async {}
}
