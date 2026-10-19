import 'package:flutter/widgets.dart';
import 'package:player/core/storage/local_store.dart';

/// Guarda da saida direta de video (Android, MediaCodec). Decodificadores
/// variam muito entre TVs e TV boxes: um com defeito pode derrubar o
/// processo nativo no meio do video, sem passar pelo Dart. A guarda marca
/// "reproduzindo com saida direta" no disco; se o app morrer com a marca
/// ligada [crashThreshold] vezes seguidas, o aparelho passa sozinho para
/// o modo compativel (`vo=gpu`). Uma reproducao encerrada normalmente zera
/// a contagem.
///
/// Ir para segundo plano (Home do controle) desliga a marca: o sistema
/// pode matar o app ali sem que isso seja falha do decodificador.
class VideoOutputGuard with WidgetsBindingObserver {
  VideoOutputGuard(this._store);

  final LocalStore _store;

  static const _key = 'video_output_guard';

  /// Quedas seguidas com a marca ligada que desativam a saida direta.
  static const crashThreshold = 2;

  bool _playing = false;
  bool _marked = false;
  int _crashes = 0;
  bool _autoCompatible = false;

  /// Saida direta desativada por quedas neste aparelho.
  bool get autoCompatible => _autoCompatible;

  /// Quedas seguidas observadas (diagnostico).
  int get consecutiveCrashes => _crashes;

  /// Le o estado e conta a queda da sessao anterior, se houve. Chamar uma
  /// vez no arranque, antes de criar o player.
  Future<void> load() async {
    try {
      final doc = await _store.read(_key);
      _crashes = (doc?['crashes'] as int?) ?? 0;
      _autoCompatible = (doc?['autoCompatible'] as bool?) ?? false;
      final leftMarked = (doc?['playing'] as bool?) ?? false;
      if (leftMarked) {
        _crashes += 1;
        if (_crashes >= crashThreshold) _autoCompatible = true;
      }
    } catch (_) {
      _crashes = 0;
      _autoCompatible = false;
    }
    await _save();
  }

  /// Reproducao com saida direta comecou.
  Future<void> playbackStarted() async {
    _playing = true;
    await _setMarked(true);
  }

  /// Reproducao terminou sem queda: zera a contagem.
  Future<void> playbackStopped() async {
    _playing = false;
    _crashes = 0;
    await _setMarked(false);
  }

  /// Usuario voltou para a saida automatica: esquece as quedas.
  Future<void> reset() async {
    _crashes = 0;
    _autoCompatible = false;
    await _save();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_playing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setMarked(false);
    } else if (state == AppLifecycleState.resumed) {
      _setMarked(true);
    }
  }

  Future<void> _setMarked(bool value) async {
    _marked = value;
    assert(() {
      debugPrint('[player-diag] guarda saida direta: marcada=$value '
          'quedas=$_crashes');
      return true;
    }());
    await _save();
  }

  Future<void> _save() async {
    try {
      await _store.write(_key, {
        'playing': _marked,
        'crashes': _crashes,
        'autoCompatible': _autoCompatible,
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }
}
