import 'package:flutter/foundation.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/services/history_service.dart';

/// Historico persistente (Fase 2): delega o comportamento em memoria e
/// grava cada mudanca no [LocalStore]. Falhas de gravacao nao bloqueiam a
/// reproducao (spec 19). Contratos inalterados.
class PersistentHistoryService extends ChangeNotifier
    implements HistoryService {
  PersistentHistoryService(this._store) {
    _inner.addListener(notifyListeners);
  }

  final LocalStore _store;
  final HistoryService _inner = InMemoryHistoryService();

  static const _key = 'history';

  /// Carrega os registros salvos. Chamar uma vez na inicializacao.
  Future<void> load() async {
    final data = await _store.read(_key);
    final rawEntries = (data?['entries'] as List?) ?? const [];
    for (final raw in rawEntries) {
      try {
        await _inner.record(
            HistoryEntry.fromMap(Map<String, Object?>.from(raw as Map)));
      } catch (_) {
        // Registro corrompido: ignora e segue com os demais (spec 7).
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(_key, {
        'entries': _inner.entries.map((entry) => entry.toMap()).toList(),
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }

  @override
  List<HistoryEntry> get entries => _inner.entries;

  @override
  HistoryEntry? latestFor(String mediaId) => _inner.latestFor(mediaId);

  @override
  Future<void> record(HistoryEntry entry) async {
    await _inner.record(entry);
    await _save();
  }

  @override
  Future<void> remove(String mediaId) async {
    await _inner.remove(mediaId);
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
