import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/library_service.dart';

/// Miniaturas de vídeos locais (spec 15.1).
///
/// No Android, extrai um frame via MediaMetadataRetriever (channel
/// `player/thumbnails`) e grava em `<support>/thumbnails/<id>.jpg`.
/// Só arquivos locais: links ficam no placeholder (pôsteres remotos
/// seguem em aberto na spec). Falha vira null — o card mostra o
/// placeholder. Fora do Android o channel não existe e sempre é null.
class ThumbnailService {
  const ThumbnailService({
    this.channel = const MethodChannel('player/thumbnails'),
    this.directoryProvider = defaultDirectory,
  });

  final MethodChannel channel;
  final Future<Directory> Function() directoryProvider;

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
    final path = await service.generateFor(stored);
    if (path == null) return;
    await library.upsert(stored.copyWith(thumbnailPath: () => path));
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
      final bytes = await channel.invokeMethod<Uint8List>('frame', {
        'path': item.source,
        'positionMs': positionMs,
        'maxWidth': maxWidth,
      });
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await directoryProvider();
      final file =
          File('${dir.path}${Platform.pathSeparator}${item.id}.jpg');
      await file.writeAsBytes(bytes);
      return file.path;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
