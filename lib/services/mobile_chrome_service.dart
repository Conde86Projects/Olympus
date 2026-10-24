import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:player/core/constants/app_constants.dart';

/// Chrome mobile: o que o aparelho mostra e esconde em volta do video.
/// Dono do estado (cheia); a tela apenas assina via [Listenable].
abstract class MobileChromeService extends ChangeNotifier {
  /// Duracao visivel do flash do toque duplo (700 ms, ADR-0002).
  static const Duration seekFlashDuration = Duration(milliseconds: 700);

  /// Texto do flash para o lado dado ('-10 s'/'+10 s', passo da fonte).
  static String formatSeekFlash(bool back) =>
      '${back ? '-' : '+'}${AppConstants.seekStep.inSeconds} s';

  /// Cheia ativa ou nao. Valor inicial sincrono: desligada.
  bool get isFullscreen;

  /// Liga/desliga a cheia (imersao + orientacao no adaptador real).
  /// Chamada repetida com o mesmo valor nao renotifica.
  Future<void> setFullscreen(bool enabled);

  /// Visibilidade atual dos controles (barra + cantos).
  bool get controlsVisible;

  /// Mostra e cancela o auto-hide pendente (abrir painel, nova sessao).
  void showControls();

  /// Oculta e cancela o auto-hide pendente (back na TV, toque).
  void hideControls();

  /// Toque: oculta se visível e permitido pelo guard; senão mostra e
  /// rearma o auto-hide (mesma condição da tela: visível e sem
  /// painel/overlay por cima).
  void toggleControls();

  /// Atividade: mostra e rearma o auto-hide.
  void pokeControls();

  /// Só cancela o auto-hide pendente, sem tocar na visibilidade
  /// (dispose da tela; o módulo sobrevive a ela).
  void cancelAutoHide();

  /// Predicado avaliado no disparo do auto-hide (painel/overlay abertos
  /// seguram o hide). Null = sempre permite.
  bool Function()? get autoHideGuard;
  set autoHideGuard(bool Function()? guard);

  /// Gancho invocado após ocultar no disparo (efeito de foco da tela).
  void Function()? get onControlsAutoHidden;
  set onControlsAutoHidden(void Function()? hook);

  /// Flash do toque duplo ('-10 s'/'+10 s'). Null = apagado.
  String? get seekFlash;

  /// true = flash a esquerda (busca para tras).
  bool get seekFlashLeft;

  /// Registra o flash do toque duplo e agenda o apagamento.
  /// O lado e a busca seguem na tela; aqui vivem so texto + timer.
  void flashSeek({required bool back});

  /// Cancela o pendente e apaga (dispose; o módulo sobrevive a tela).
  void resetSeekFlash();
}

/// Adaptador real (mobile): imersao + paisagem via `SystemChrome`.
///
/// Extracao fiel de `_applyMobileFullscreen` do player screen:
/// mesma ordem de chamadas, mesmos parametros
/// (`immersiveSticky` + paisagem na entrada; `edgeToEdge` + `const []`
/// na saida).
class SystemMobileChrome extends MobileChromeService {
  bool _fullscreen = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _seekFlash;
  bool _seekFlashLeft = false;
  Timer? _seekFlashTimer;

  @override
  bool get isFullscreen => _fullscreen;

  @override
  bool get controlsVisible => _controlsVisible;

  @override
  bool Function()? autoHideGuard;

  @override
  void Function()? onControlsAutoHidden;

  @override
  void showControls() {
    _cancelPending();
    if (_controlsVisible) return;
    _controlsVisible = true;
    notifyListeners();
  }

  @override
  void hideControls() {
    _cancelPending();
    if (!_controlsVisible) return;
    _controlsVisible = false;
    notifyListeners();
  }

  @override
  void toggleControls() {
    if (_controlsVisible && _mayAutoHide()) {
      hideControls();
    } else {
      pokeControls();
    }
  }

  @override
  void pokeControls() {
    _cancelPending();
    _hideTimer = Timer(AppConstants.controlsAutoHide, _fireAutoHide);
    // Notifica sempre (mesmo já visível): a atividade agenda um frame,
    // e a tela agenda pós-frame em cima dele (abrir painel pelo atalho).
    _controlsVisible = true;
    notifyListeners();
  }

  @override
  void cancelAutoHide() {
    _cancelPending();
  }

  void _cancelPending() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  bool _mayAutoHide() => autoHideGuard == null || autoHideGuard!();

  void _fireAutoHide() {
    _hideTimer = null;
    if (_mayAutoHide()) {
      _controlsVisible = false;
      notifyListeners();
      onControlsAutoHidden?.call();
    }
  }

  @override
  String? get seekFlash => _seekFlash;

  @override
  bool get seekFlashLeft => _seekFlashLeft;

  @override
  void flashSeek({required bool back}) {
    _seekFlashTimer?.cancel();
    _seekFlash = MobileChromeService.formatSeekFlash(back);
    _seekFlashLeft = back;
    notifyListeners();
    _seekFlashTimer =
        Timer(MobileChromeService.seekFlashDuration, () {
      _seekFlashTimer = null;
      _seekFlash = null;
      notifyListeners();
    });
  }

  @override
  void resetSeekFlash() {
    _seekFlashTimer?.cancel();
    _seekFlashTimer = null;
    if (_seekFlash == null) return;
    _seekFlash = null;
    notifyListeners();
  }

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
/// Visibilidade congelada em visível (estado inicial da tela).
class NoOpMobileChrome extends MobileChromeService {
  @override
  bool get isFullscreen => false;

  @override
  Future<void> setFullscreen(bool enabled) async {}

  @override
  bool get controlsVisible => true;

  @override
  void showControls() {}

  @override
  void hideControls() {}

  @override
  void toggleControls() {}

  @override
  void pokeControls() {}

  @override
  void cancelAutoHide() {}

  @override
  bool Function()? get autoHideGuard => null;

  @override
  set autoHideGuard(bool Function()? guard) {}

  @override
  void Function()? get onControlsAutoHidden => null;

  @override
  set onControlsAutoHidden(void Function()? hook) {}

  @override
  String? get seekFlash => null;

  @override
  bool get seekFlashLeft => false;

  @override
  void flashSeek({required bool back}) {}

  @override
  void resetSeekFlash() {}
}
