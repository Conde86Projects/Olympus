import 'package:flutter/services.dart';

/// Permissão de mídia em runtime no Android (F8-runtime, Fase 4b).
///
/// O manifest declara `READ_MEDIA_VIDEO` (33+) / `READ_EXTERNAL_STORAGE`
/// (≤32); este serviço consulta e pede via channel nativo antes de abrir
/// arquivo local. Fora do Android o channel não existe
/// ([MissingPluginException]) e o acesso é liberado: desktop não pede
/// permissão de runtime. Negar não trava: o open falha e o overlay F9
/// explica que o problema é da fonte.
class MediaPermissionService {
  const MediaPermissionService(
      {this.channel = const MethodChannel('player/media_permission')});

  final MethodChannel channel;

  /// true quando já tem acesso (ou a plataforma não pede).
  Future<bool> get hasAccess async {
    try {
      return await channel.invokeMethod<String>('status') == 'granted';
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Garante acesso, mostrando o diálogo do sistema se preciso.
  /// Devolve true quando concedido.
  Future<bool> ensureAccess() async {
    if (await hasAccess) return true;
    try {
      return await channel.invokeMethod<String>('request') == 'granted';
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }
}
