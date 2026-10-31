import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/thumbnail_service.dart';

/// Biblioteca local do usuario (spec 15.1). Notifica ouvintes a cada mudanca.
/// Remover um item nunca apaga o arquivo original (spec 15.2).
abstract class LibraryService extends ChangeNotifier {
  List<MediaItem> get items;
  List<MediaItem> get favorites;

  MediaItem? findById(String id);
  MediaItem? findBySource(String source);

  /// Insere ou atualiza (mesmo [source] reutiliza o id existente).
  Future<MediaItem> upsert(MediaItem item);

  Future<void> toggleFavorite(String id);
  Future<void> remove(String id);

  /// Apaga todos os itens do catalogo local. Nunca apaga arquivos
  /// (diagnostico "limpar dados", spec 6.1).
  Future<void> clear();
}

/// Implementacao em memoria para o prototipo (Fase 1).
class InMemoryLibraryService extends ChangeNotifier
    implements LibraryService {
  InMemoryLibraryService({this.thumbnailService = const ThumbnailService()});

  /// Servico usado so para apagar <id>.jpg no remove/clear.
  final ThumbnailService thumbnailService;

  final Map<String, MediaItem> _items = {};

  @override
  List<MediaItem> get items {
    final list = _items.values.toList();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List.unmodifiable(list);
  }

  @override
  List<MediaItem> get favorites =>
      List.unmodifiable(items.where((item) => item.isFavorite));

  @override
  MediaItem? findById(String id) => _items[id];

  @override
  MediaItem? findBySource(String source) {
    for (final item in _items.values) {
      if (item.source == source) return item;
    }
    return null;
  }

  @override
  Future<MediaItem> upsert(MediaItem item) async {
    final existing = findBySource(item.source);
    final merged = existing == null
        ? item
        : existing.copyWith(
            title: item.title,
            // Miniatura entrante vale; null entrante preserva a
            // gravada (sem isso, re-adicionar apagava o thumb e a
            // geracao de fundo nunca persistia — mesclagem por
            // source reaproveita o item existente).
            thumbnailPath: () =>
                item.thumbnailPath ?? existing.thumbnailPath,
            duration: () => item.duration,
            lastPosition: () => item.lastPosition,
            lastPlayedAt: () => item.lastPlayedAt,
          );
    _items[merged.id] = merged;
    notifyListeners();
    return merged;
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = _items[id];
    if (item == null) return;
    _items[id] = item.copyWith(isFavorite: !item.isFavorite);
    notifyListeners();
  }

  @override
  Future<void> remove(String id) async {
    if (_items.remove(id) != null) notifyListeners();
    // O arquivo sai em segundo plano: a entrada do mapa nunca espera
    // pelo disco (o pumpAndSettle dos testes tambem nao espera).
    unawaited(ThumbnailService.deleteFor(id, service: thumbnailService));
  }

  @override
  Future<void> clear() async {
    if (_items.isEmpty) return;
    final ids = _items.keys.toList();
    _items.clear();
    notifyListeners();
    for (final id in ids) {
      unawaited(ThumbnailService.deleteFor(id, service: thumbnailService));
    }
  }
}
