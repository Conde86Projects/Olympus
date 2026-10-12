import 'package:flutter/services.dart';

/// Detecção de Android TV / Leanback via channel nativo.
///
/// O [MainActivity] responde `isTv` com true quando o aparelho tem o
/// recurso `leanback` ou o modo de UI é televisão. Fora do Android o
/// channel não existe ([MissingPluginException]) e o resultado é false:
/// desktop nunca é TV. Erro de plataforma também vira false — a
/// detecção nunca trava o arranque.
class TvInfoService {
  const TvInfoService(
      {this.channel = const MethodChannel('player/tv_info')});

  final MethodChannel channel;

  /// true quando o aparelho é uma TV (Leanback).
  Future<bool> get isTv async {
    try {
      return await channel.invokeMethod<bool>('isTv') == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
