import 'package:flutter/foundation.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/library_service.dart';

/// Biblioteca persistente (Fase 2): delega o comportamento em memoria e
/// grava cada mudanca no [LocalStore]. Falhas de gravacao nao bloqueiam a
/// UI (spec 19). Contratos inalterados.
class PersistentLibraryService extends ChangeNotifier
    implements LibraryService {
  PersistentLibraryService(this._store) {
    _inner.addListener(notifyListeners);
  }

  final LocalStore _store;
  final LibraryService _inner = InMemoryLibraryService();

  static const _key = 'library';

  /// Carrega os itens salvos. Chamar uma vez na inicializacao.
  Future<void> load() async {
    final data = await _store.read(_key);
    final rawItems = (data?['items'] as List?) ?? const [];
    for (final raw in rawItems) {
      try {
        await _inner
            .upsert(MediaItem.fromMap(Map<String, Object?>.from(raw as Map)));
      } catch (_) {
        // Item corrompido: ignora e segue com os demais (spec 7).
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(_key, {
        'items': _inner.items.map((item) => item.toMap()).toList(),
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }

  @override
  List<MediaItem> get items => _inner.items;

  @override
  List<MediaItem> get favorites => _inner.favorites;

  @override
  MediaItem? findById(String id) => _inner.findById(id);

  @override
  MediaItem? findBySource(String source) => _inner.findBySource(source);

  @override
  Future<MediaItem> upsert(MediaItem item) async {
    final saved = await _inner.upsert(item);
    await _save();
    return saved;
  }

  @override
  Future<void> toggleFavorite(String id) async {
    await _inner.toggleFavorite(id);
    await _save();
  }

  @override
  Future<void> remove(String id) async {
    await _inner.remove(id);
    await _save();
  }

  @override
  Future<void> clear() async {
    await _inner.clear();
    await _save();
  }

  @override
  void dispose() {
    _inner.removeListener(notifyListeners);
    _inner.dispose();
    super.dispose();
  }
}
