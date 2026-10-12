/// Erros da aplicacao com formato unico: todo erro carrega um [code] legivel
/// por maquina e uma [message] pronta para exibicao (spec 17).
sealed class AppError implements Exception {
  const AppError(this.code, this.message);

  /// Codigo estavel, ex. "media.incompatible". Usado em logs e testes.
  final String code;

  /// Mensagem em pt-BR para exibir ao usuario.
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Midia incompativel, arquivo removido ou formato nao suportado.
class MediaError extends AppError {
  const MediaError(super.code, super.message);

  const MediaError.incompatible()
      : super('media.incompatible',
            'Não foi possível reproduzir este arquivo neste dispositivo.');

  const MediaError.missingFile()
      : super('media.missing-file',
            'Este arquivo não está mais disponível no caminho salvo.');
}

/// Falha de rede ou link indisponivel (spec 17.2, 17.3).
class NetworkError extends AppError {
  const NetworkError(super.code, super.message);

  const NetworkError.unavailableLink()
      : super('network.unavailable-link',
            'Não foi possível carregar este link. Verifique a conexão ou confirme se o endereço ainda está disponível.');

  const NetworkError.offline()
      : super('network.offline',
            'Não há conexão suficiente para carregar este conteúdo.');
}

/// Entrada invalida fornecida pelo usuario (validada na borda, spec 10).
class ValidationError extends AppError {
  const ValidationError(super.code, super.message);

  const ValidationError.emptyUrl()
      : super('validation.empty-url', 'Informe o endereço do vídeo.');

  const ValidationError.malformedUrl()
      : super(
            'validation.malformed-url', 'Esse endereço não parece um link válido.');
}

/// Manifesto ou operacao de add-on invalida (spec 4.1.1, 6.1).
class AddonError extends AppError {
  const AddonError(super.code, super.message);

  const AddonError.invalidManifest(String reason)
      : super('addon.invalid-manifest', reason);

  const AddonError.notFound()
      : super('addon.not-found', 'Add-on não encontrado.');

  const AddonError.alreadyInstalled()
      : super('addon.already-installed', 'Este add-on já está instalado.');

  const AddonError.unavailable()
      : super('addon.unavailable', 'Fonte indisponível no momento.');

  const AddonError.disabled()
      : super('addon.disabled', 'Ative o add-on para usar este conteúdo.');

  const AddonError.fetchFailed(String reason)
      : super('addon.fetch-failed', reason);

  const AddonError.repoExists()
      : super('addon.repo-exists', 'Este endereço já está cadastrado.');

  const AddonError.repoNotFound()
      : super('addon.repo-not-found', 'Repositório não encontrado.');

  const AddonError.noUpdate()
      : super('addon.no-update', 'Nenhuma atualização disponível.');

  const AddonError.incompatible()
      : super('addon.incompatible',
            'Esta versão não é compatível com esta plataforma.');

  const AddonError.noBackup()
      : super('addon.no-backup', 'Sem versão anterior para restaurar.');
}

/// Falha de persistencia local. Nunca deve interromper a reproducao (spec 19).
class StorageError extends AppError {
  const StorageError(super.code, super.message);

  const StorageError.unavailable()
      : super('storage.unavailable',
            'Não foi possível salvar este dado localmente.');
}
