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
