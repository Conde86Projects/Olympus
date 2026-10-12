import 'package:flutter/foundation.dart';
import 'package:player/models/history_entry.dart';

/// Historico local de reproducao (spec 15.3). Limpar o historico nunca apaga
/// arquivos locais. Falhas de persistencia nao bloqueiam a reproducao (19).
abstract class HistoryService extends ChangeNotifier {
  /// Ordenado do mais recente para o mais antigo.
  List<HistoryEntry> get entries;

  HistoryEntry? latestFor(String mediaId);

  Future<void> record(HistoryEntry entry);
  Future<void> remove(String mediaId);
  Future<void> clear();
}

/// Implementacao em memoria para o prototipo (Fase 1).
class InMemoryHistoryService extends ChangeNotifier
    implements HistoryService {
  final Map<String, HistoryEntry> _entries = {};

  @override
  List<HistoryEntry> get entries {
    final list = _entries.values.toList();
    list.sort((a, b) => b.accessedAt.compareTo(a.accessedAt));
    return List.unmodifiable(list);
  }

  @override
  HistoryEntry? latestFor(String mediaId) => _entries[mediaId];

  @override
  Future<void> record(HistoryEntry entry) async {
    _entries[entry.mediaId] = entry;
    notifyListeners();
  }

  @override
  Future<void> remove(String mediaId) async {
    if (_entries.remove(mediaId) != null) notifyListeners();
  }

  @override
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
