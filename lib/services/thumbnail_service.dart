import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/mpv_frame_grabber.dart';

/// Miniaturas de vídeos locais (spec 15.1).
///
/// No Android, extrai um frame via MediaMetadataRetriever (channel
/// `player/thumbnails`) e grava em `<support>/thumbnails/<id>.jpg`.
/// Só arquivos locais: links ficam no placeholder (pôsteres remotos
/// seguem em aberto na spec). Falha vira null — o card mostra o
/// placeholder. Onde o channel não existe (Windows), o quadro vem do motor do
/// app por [fallbackFrame].
class ThumbnailService {
  const ThumbnailService({
    this.channel = const MethodChannel('player/thumbnails'),
    this.directoryProvider = defaultDirectory,
    this.fallbackFrame = MpvFrameGrabber.grab,
  });

  final MethodChannel channel;
  final Future<Directory> Function() directoryProvider;

  /// Quadro do vídeo em `path`, já reduzido a `maxWidth`, para quando não há
  /// o channel nativo. Devolve null quando não consegue.
  final Future<Uint8List?> Function(String path, int maxWidth) fallbackFrame;

  static Future<Directory> defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir =
        Directory('${support.path}${Platform.pathSeparator}thumbnails');
    await dir.create(recursive: true);
    return dir;
  }

  /// Preenche a miniatura de [item] quando falta: gera e grava via
  /// [service], persistindo no [library]. Consulta o item ARMAZENADO
  /// (a cópia da rota pode estar obsoleta). Falha vira nada —
  /// o placeholder cobre.
  static Future<void> backfill(
    LibraryService library,
    MediaItem item, {
    ThumbnailService service = const ThumbnailService(),
  }) async {
    final stored = library.findById(item.id) ?? item;
    if (stored.sourceType != MediaSourceType.local ||
        stored.thumbnailPath != null) {
      return;
    }
    // Abrir um vídeo novo pede a miniatura mais de uma vez quase junto: o
    // segundo pedido espera o primeiro em vez de gerar de novo.
    final running = _running[stored.id];
    if (running != null) {
      await running;
      return;
    }
    final work = _generateAndStore(library, stored, service);
    _running[stored.id] = work;
    try {
      await work;
    } finally {
      _running.remove(stored.id);
    }
  }

  static final _running = <String, Future<void>>{};

  static Future<void> _generateAndStore(
    LibraryService library,
    MediaItem stored,
    ThumbnailService service,
  ) async {
    final path = await service.generateFor(stored);
    if (path == null) return;
    // Relê: gerar leva segundos, e o upsert copia a posição do item que
    // chega. Com a cópia velha, sair do player antes apagaria o ponto salvo.
    final fresh = library.findById(stored.id) ?? stored;
    await library.upsert(fresh.copyWith(thumbnailPath: () => path));
  }

  /// Gera e grava a miniatura de [item]; devolve o caminho ou null.
  Future<String?> generateFor(
    MediaItem item, {
    int positionMs = 3000,
    int maxWidth = 320,
  }) async {
    if (item.sourceType != MediaSourceType.local) return null;
    if (!File(item.source).existsSync()) return null;
    try {
      final bytes = await _frame(item.source, positionMs, maxWidth);
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await directoryProvider();
      final file =
          File('${dir.path}${Platform.pathSeparator}${item.id}.jpg');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _frame(String path, int positionMs, int maxWidth) async {
    try {
      return await channel.invokeMethod<Uint8List>('frame', {
        'path': path,
        'positionMs': positionMs,
        'maxWidth': maxWidth,
      });
    } on MissingPluginException {
      return fallbackFrame(path, maxWidth);
    }
  }

  /// Apaga a miniatura de [id] (<dir>/<id>.jpg). Falha ou ausencia
  /// vira nada: a remocao do item nunca trava por causa do arquivo.
  /// Nunca toca na midia de origem.
  static Future<void> deleteFor(
    String id, {
    ThumbnailService service = const ThumbnailService(),
  }) async {
    try {
      final dir = await service.directoryProvider();
      final file = File('${dir.path}${Platform.pathSeparator}$id.jpg');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // No-op: item removido segue removido.
    }
  }
}
