import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// Controle da janela do desktop (spec 14): tela cheia, sempre no topo e
/// modo compacto. Telas dependem deste contrato; os testes usam [NoOpWindowService].
abstract class WindowService {
  Future<void> setFullscreen(bool enabled);
  Future<void> setAlwaysOnTop(bool enabled);

  /// Janela pequena flutuante para assistir enquanto trabalha (spec 14.4).
  Future<void> setCompact(bool enabled);

  Future<bool> get isFullscreen;
  Future<bool> get isCompact;

  /// Emite a cada minimizar da janela. O player grava a posicao sem
  /// pausar: no Windows o ciclo de vida do Flutter nao chega como
  /// `hidden` com o window_manager na frente das mensagens da janela.
  Stream<void> get minimized;
}

/// Implementacao real sobre window_manager (Windows/Linux).
class WindowManagerService with WindowListener implements WindowService {
  /// Chamado ao fim de cada mover/redimensionar, com a geometria atual.
  /// O `main` usa para persistir tamanho e posicao (spec 14.1).
  Future<void> Function(Rect bounds)? onBoundsChanged;

  Size? _restoredSize;
  bool _compact = false;
  final _minimized = StreamController<void>.broadcast();

  /// Tamanho inicial e minimo da janela (Fase 2). O minimo e o do
  /// compacto: assistir numa janela pequena e o uso central, e com
  /// 800x600 o Windows prendia o compacto e o arrasto nesse piso.
  /// Abaixo de `PlayerControls.denseMaxHeight` o player usa o card de uma
  /// fileira; menus rolam em vez de estourar.
  static const initialSize = Size(1280, 720);
  static const compactSize = Size(480, 270);
  static const minimumSize = compactSize;

  /// Aplica a geometria inicial apos o `runApp` (nunca antes: operacoes
  /// de janela antes do primeiro frame deixam a tela branca no Windows).
  /// Chamar no `main` com as preferencias ja carregadas. Liga a escuta
  /// que persiste tamanho e posicao a cada mover/redimensionar.
  Future<void> applyStartupGeometry({
    required String title,
    required bool alwaysOnTop,
    required bool startInFullscreen,
    Rect? restoredBounds,
  }) async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    final size = restoredBounds?.size ?? initialSize;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        minimumSize: minimumSize,
        center: restoredBounds == null,
        title: title,
        alwaysOnTop: alwaysOnTop,
        fullScreen: startInFullscreen,
      ),
    );
    if (restoredBounds != null && !startInFullscreen) {
      await windowManager.setPosition(restoredBounds.topLeft);
    }
    await windowManager.show();
  }

  @override
  void onWindowResized() => _saveBounds();

  @override
  void onWindowMoved() => _saveBounds();

  @override
  void onWindowMinimize() => _minimized.add(null);

  @override
  Stream<void> get minimized => _minimized.stream;

  /// Persiste a geometria normal da janela. Ignora tela cheia, maximizada
  /// e modo compacto para nao restaurar um estado transitorio.
  Future<void> _saveBounds() async {
    if (_compact) return;
    try {
      if (await windowManager.isFullScreen()) return;
      if (await windowManager.isMaximized()) return;
      final bounds = await windowManager.getBounds();
      await onBoundsChanged?.call(bounds);
    } catch (_) {
      // Falha de leitura/persistencia nao afeta a janela (spec 19).
    }
  }

  @override
  Future<void> setFullscreen(bool enabled) =>
      windowManager.setFullScreen(enabled);

  @override
  Future<void> setAlwaysOnTop(bool enabled) =>
      windowManager.setAlwaysOnTop(enabled);

  @override
  Future<void> setCompact(bool enabled) async {
    if (enabled == _compact) return;
    if (enabled) {
      _restoredSize = await windowManager.getSize();
      await windowManager.setSize(compactSize);
      await windowManager.setAlwaysOnTop(true);
      _compact = true;
    } else {
      final size = _restoredSize ?? initialSize;
      await windowManager.setSize(size);
      await windowManager.setAlwaysOnTop(false);
      _compact = false;
    }
  }

  @override
  Future<bool> get isFullscreen => windowManager.isFullScreen();

  @override
  Future<bool> get isCompact async => _compact;
}

/// Implementacao neutra para testes e plataformas sem janela gerenciavel.
class NoOpWindowService implements WindowService {
  bool _fullscreen = false;
  bool _compact = false;
  final _minimized = StreamController<void>.broadcast();

  /// Testes: simula o minimizar da janela.
  void simulateMinimize() => _minimized.add(null);

  @override
  Stream<void> get minimized => _minimized.stream;

  @override
  Future<void> setFullscreen(bool enabled) async => _fullscreen = enabled;

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {}

  @override
  Future<void> setCompact(bool enabled) async => _compact = enabled;

  @override
  Future<bool> get isFullscreen async => _fullscreen;

  @override
  Future<bool> get isCompact async => _compact;
}
