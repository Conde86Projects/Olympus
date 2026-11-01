import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player/core/utils/frame_downscale.dart';

/// Quadro de um vídeo local tirado pelo próprio motor do app (libmpv), para
/// as plataformas sem o channel `player/thumbnails` (Windows, Linux, macOS).
/// Não depende de ferramenta instalada e abre qualquer formato que o player
/// abre. Só um quadro por vez: um segundo motor decodificando junto com o
/// vídeo em reprodução já basta; vários seriam pesados.
class MpvFrameGrabber {
  const MpvFrameGrabber._();

  /// Ligado no arranque, depois de `MediaKit.ensureInitialized()`. Desligado
  /// (padrão e nos testes), [grab] devolve null sem tocar no motor.
  static bool enabled = false;

  /// Espera antes de abrir o motor, para a transição de tela terminar: criar
  /// o motor trava a interface por alguns quadros.
  static Duration settle = const Duration(milliseconds: 1500);

  /// Limite para o motor reconhecer o arquivo e para entregar o quadro.
  /// Arquivo cortado ou que não é vídeo estoura aqui e vira null.
  static const timeout = Duration(seconds: 5);

  /// Posição do quadro: 5% do vídeo. Passa da abertura preta e dos créditos e
  /// serve até para clipes de um segundo.
  static const _start = '5%';

  static Future<void> _tail = Future<void>.value();

  /// Quadro do vídeo em [path] reduzido para no máximo [maxWidth] de largura
  /// (JPEG), ou null quando falta o quadro (só áudio, arquivo ilegível,
  /// tempo esgotado).
  static Future<Uint8List?> grab(String path, int maxWidth) async {
    if (!enabled) return null;
    await Future<void>.delayed(settle);
    return serialized(() => _grab(path, maxWidth));
  }

  /// Executa [task] depois das anteriores. Falha de uma não impede as
  /// seguintes.
  @visibleForTesting
  static Future<T> serialized<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Faixa de verdade: o motor também lista as opções "auto" e "no".
  static bool _hasReal(List<dynamic> tracks) =>
      tracks.any((t) => t.id != 'auto' && t.id != 'no');

  static Future<Uint8List?> _grab(String path, int maxWidth) async {
    final player = Player();
    try {
      final native = player.platform as NativePlayer;
      await native.setProperty('vid', 'auto');
      await native.setProperty('aid', 'no');
      await native.setProperty('sid', 'no');
      await native.setProperty('ao', 'null');
      await native.setProperty('hwdec', 'no');
      await native.setProperty('start', _start);
      await player.open(Media(Uri.file(path).toString()), play: false);
      // Só áudio não tem quadro: sai agora em vez de esperar o limite.
      final tracks = await player.stream.tracks
          .firstWhere((t) => _hasReal(t.video) || _hasReal(t.audio))
          .timeout(timeout);
      if (!_hasReal(tracks.video)) return null;
      await player.stream.videoParams
          .firstWhere((params) => (params.w ?? 0) > 0)
          .timeout(timeout);
      // O primeiro quadro decodificado ainda não está disponível para captura.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final frame = await player
          .screenshot(format: 'image/jpeg')
          .timeout(timeout);
      if (frame == null || frame.isEmpty) return null;
      return await downscaleJpegAsync(frame, maxWidth);
    } catch (_) {
      return null;
    } finally {
      unawaited(player.dispose());
    }
  }
}
