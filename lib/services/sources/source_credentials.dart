import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Armazenamento de credenciais por fonte (5C): uma chave opaca por
/// id de fonte (token/chave de API/senha, conforme o adaptador).
/// Segredos nunca vao para URL, log, manifesto ou JSON exportado.
abstract class SourceCredentialStore {
  const SourceCredentialStore();

  /// Guarda (ou substitui) o segredo da fonte.
  Future<void> save(String sourceId, String secret);

  /// Le o segredo, ou null quando ausente.
  Future<String?> read(String sourceId);

  /// Apaga o segredo. Ausente nao e erro.
  Future<void> delete(String sourceId);
}

/// Memoria (testes e sessoes efemeras). Nao persiste.
class InMemoryCredentialStore implements SourceCredentialStore {
  InMemoryCredentialStore();

  final Map<String, String> _secrets = {};

  @override
  Future<void> save(String sourceId, String secret) async {
    _secrets[sourceId] = secret;
  }

  @override
  Future<String?> read(String sourceId) async => _secrets[sourceId];

  @override
  Future<void> delete(String sourceId) async {
    _secrets.remove(sourceId);
  }
}

/// Costura minima do backend seguro, para testar a loja sem plugin
/// nativo (o plugin so existe no aparelho/desktop real).
abstract class SecureCredentialBackend {
  const SecureCredentialBackend();

  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// Backend real: Keystore (Android) / Keychain (iOS/macOS) /
/// Credential Manager (Windows) / Secret Service (Linux).
class FlutterSecureStorageBackend implements SecureCredentialBackend {
  const FlutterSecureStorageBackend([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Loja segura (producao): delega ao backend com prefixo por app.
/// Chaves nunca saem daqui para logs ou manifestos.
class SecureCredentialStore implements SourceCredentialStore {
  const SecureCredentialStore(this.backend);

  final SecureCredentialBackend backend;

  static String _key(String sourceId) => 'player.source.$sourceId';

  @override
  Future<void> save(String sourceId, String secret) =>
      backend.write(_key(sourceId), secret);

  @override
  Future<String?> read(String sourceId) => backend.read(_key(sourceId));

  @override
  Future<void> delete(String sourceId) => backend.delete(_key(sourceId));
}
