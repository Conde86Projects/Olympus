/// Armazenamento local chave-valor (spec 19). Borda de persistencia: as
/// implementacoes futuras (ex. shared_preferences, sqlite) entram aqui sem
/// tocar nos servicos. Falhas devem virar erro de armazenamento e nunca
/// travar a UI.
abstract class LocalStore {
  Future<Map<String, Object?>?> read(String key);
  Future<void> write(String key, Map<String, Object?> value);
  Future<void> remove(String key);
  Future<void> clear();
}

/// Implementacao em memoria para o prototipo (Fase 1).
class InMemoryLocalStore implements LocalStore {
  final Map<String, Map<String, Object?>> _data = {};

  @override
  Future<Map<String, Object?>?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    _data[key] = Map.of(value);
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async => _data.clear();
}
