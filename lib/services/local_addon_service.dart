import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/addon_package.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/sources/source_adapter.dart';
import 'package:player/services/sources/source_credentials.dart';

/// Implementacao local do gerenciador (spec 6.1): estado em memoria com
/// persistencia JSON no [LocalStore]. Falhas de gravacao nao bloqueiam a
/// UI (spec 19); entradas corrompidas sao ignoradas na carga (spec 7).
class LocalAddonService extends ChangeNotifier implements AddonService {
  LocalAddonService(
    this._store, {
    String? platform,
    Set<String>? faultyIds,
    AddonFetcher fetcher = const HttpAddonFetcher(),
    List<SourceAdapter> adapters = const [],
    SourceCredentialStore? credentials,
    Directory? packageDir,
    bool Function()? allowUnknownSources,
  })  : _platform = platform ?? Platform.operatingSystem,
        _faultyIds = faultyIds ?? const {},
        _fetcher = fetcher,
        _adapters = adapters,
        _credentials = credentials ?? InMemoryCredentialStore(),
        _allowUnknownSources = allowUnknownSources ?? (() => true),
        _packageDir = packageDir;

  final LocalStore _store;
  final AddonFetcher _fetcher;

  /// Adaptadores por fonte (5C). Vazio = so o formato generico
  /// `{"items": [...]}`; cada URL casa no maximo um adaptador.
  final List<SourceAdapter> _adapters;
  final SourceCredentialStore _credentials;
  /// Libera a entrada de origens novas. O padrao `() => true` mantem
  /// os testes e fluxos existentes; o app injeta a preferencia (T1).
  /// A regra fica no servico: so bloquear na tela seria contornado
  /// pelo fluxo de repositorios.
  final bool Function() _allowUnknownSources;
  final Directory? _packageDir;
  @override
  bool get unknownSourcesAllowed => _allowUnknownSources();
  final String _platform;

  @override
  String get platform => _platform;

  /// Ids que simulam defeito (isolamento, §26.14). Costura de teste: na
  /// Fase 6 o defeito vira de excecoes reais da integracao.
  final Set<String> _faultyIds;
  final Map<String, AddonInfo> _items = {};
  final Map<String, AddonRepository> _repos = {};

  /// Ultima instalacao/ativacao, para a recuperacao do modo seguro.
  /// Desativar/desinstalar nao registram: sao a propria recuperacao.
  Map<String, Object?>? _lastChange;

  /// Backup integral pre-update (id -> AddonInfo serializado), para o
  /// rollback de um nivel. Persistido junto com os instalados.
  final Map<String, Map<String, Object?>> _previous = {};

  /// Chave do documento de instalados. Publica porque o guarda de
  /// arranque ([StartupGuard]) le e desativa a ultima alteracao direto
  /// no documento quando o servico nem foi carregado (modo seguro).
  static const storeKey = 'addons';
  static const _reposKey = 'addon_repos';

  /// Carrega instalados e repositorios. Chamar uma vez na
  /// inicializacao.
  Future<void> load() async {
    final data = await _store.read(storeKey);
    final rawItems = (data?['items'] as List?) ?? const [];
    for (final raw in rawItems) {
      try {
        final info =
            AddonInfo.fromMap(Map<String, Object?>.from(raw as Map));
        _items[info.manifest.id] = info;
      } catch (_) {
        // Entrada corrompida: ignora e segue com as demais (spec 7).
      }
    }
    final rawChange = data?['lastChange'];
    _lastChange =
        rawChange is Map ? Map<String, Object?>.from(rawChange) : null;
    final rawPrevious = data?['previous'];
    if (rawPrevious is Map) {
      for (final entry in rawPrevious.entries) {
        try {
          if (entry.key is! String || entry.value is! Map) continue;
          final backup =
              Map<String, Object?>.from(entry.value as Map);
          // Valida na carga: backup corrompido e descartado.
          AddonInfo.fromMap(backup);
          _previous[entry.key as String] = backup;
        } catch (_) {
          // Backup corrompido: descarta e segue (spec 7).
        }
      }
    }
    final repoData = await _store.read(_reposKey);
    final rawRepos = (repoData?['items'] as List?) ?? const [];
    for (final raw in rawRepos) {
      try {
        final repo =
            AddonRepository.fromMap(Map<String, Object?>.from(raw as Map));
        _repos[repo.id] = repo;
      } catch (_) {
        // Entrada corrompida: ignora e segue com as demais (spec 7).
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(storeKey, {
        'items': _items.values.map((info) => info.toMap()).toList(),
        'lastChange': _lastChange,
        'previous': _previous,
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }

  Future<void> _saveRepos() async {
    try {
      await _store.write(_reposKey, {
        'items': _repos.values.map((repo) => repo.toMap()).toList(),
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }

  @override
  List<AddonInfo> get addons {
    final list = _items.values.toList()
      ..sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
    return List.unmodifiable(list);
  }

  @override
  AddonInfo? findById(String addonId) => _items[addonId];

  @override
  AddonState getStatus(String addonId) => _require(addonId).state;

  AddonInfo _require(String addonId) {
    final info = _items[addonId];
    if (info == null) throw const AddonError.notFound();
    return info;
  }

  @override
  Future<AddonManifest> validate(Map<String, Object?> json) async =>
      AddonManifest.fromMap(json);

  @override
  Future<AddonManifest> fetchManifest(String url) async =>
      AddonManifest.parseJson(await _fetcher.fetchText(url));

  @override
  Future<AddonInfo> install(
    AddonManifest manifest, {
    required bool originTrusted,
  }) async {
    if (!_allowUnknownSources() && !originTrusted) {
      throw const AddonError.unknownSourcesDisabled();
    }
    if (_items.containsKey(manifest.id)) {
      throw const AddonError.alreadyInstalled();
    }
    final info = AddonInfo(
      manifest: manifest,
      originTrusted: originTrusted,
      packageOrigin: AddonPackageOrigin.manifest,
      installedAt: DateTime.now(),
      // Instalar e aprovar: a revisao humana ja aconteceu.
      approvedOrigin: _hostOf(manifest.catalogUrl),
    );
    _items[manifest.id] = info;
    _recordChange(manifest.id, manifest.name, 'install');
    notifyListeners();
    await _save();
    return info;
  }

  void _recordChange(String id, String name, String kind) {
    _lastChange = {
      'id': id,
      'name': name,
      'kind': kind,
      'at': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<void> enable(String addonId) async {
    final info = _require(addonId);
    // Origem nova exige aprovacao explicita antes de ativar (sem
    // excecao, como a incompatibilidade).
    if (info.needsApproval) {
      await _update(info.copyWith(
        state: AddonState.inactive,
        diagnostic: () => approvalDiagnostic,
      ));
      return;
    }
    if (!info.manifest.supports(_platform)) {
      await _update(info.copyWith(
        state: AddonState.inactive,
        diagnostic: () =>
            'Este add-on não é compatível com esta plataforma.',
      ));
      return;
    }
    _recordChange(info.manifest.id, info.manifest.name, 'enable');
    await _update(info.copyWith(
      state: AddonState.active,
      diagnostic: () => null,
    ));
  }

  @override
  Future<void> clearError(String addonId) async {
    final info = _require(addonId);
    if (info.state != AddonState.error) return;
    final blocked = info.needsApproval
        ? approvalDiagnostic
        : !info.manifest.supports(_platform)
            ? 'Este add-on não é compatível com esta plataforma.'
            : null;
    await _update(info.copyWith(
      state: blocked == null ? AddonState.active : AddonState.error,
      diagnostic: () => blocked,
    ));
  }

  @override
  Future<void> disable(String addonId) async {
    final info = _require(addonId);
    await _update(info.copyWith(
      state: AddonState.inactive,
      diagnostic: () => null,
    ));
  }

  /// Lê e valida um pacote sem salvar nada: a revisão mostra o que
  /// vai entrar antes de confirmar. Roda fora da thread da interface.
  @override
  Future<AddonPackage> previewPackage(Uint8List zipBytes) async {
    if (!_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    return compute(readAddonPackage, zipBytes);
  }

  /// Link com progresso e cancelamento (T3): baixa em memória e
  /// cai na mesma revisão do arquivo. Sem temporário por construção.
  @override
  Future<AddonPackage> previewPackageFromLink(
    String url, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    if (!_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    final bytes = await _fetcher.fetchBytes(
      url,
      onProgress: onProgress,
      cancel: cancel,
    );
    return previewPackage(bytes);
  }

  /// Arquivos que um pacote validado grava na pasta da versao.
  static Map<String, List<int>> _payloadOf(AddonPackage package) => {
        if (package.catalogJson != null)
          'catalog.json': utf8.encode(package.catalogJson!),
        if (package.icon != null) 'icon.png': package.icon!,
        if (package.fanart != null) 'fanart.jpg': package.fanart!,
      };

  /// Grava o payload na pasta da versao via temporario + rename: falha
  /// no meio nao deixa pasta nem registro. Devolve a pasta final.
  Future<Directory> _writePackageDir(
    String id,
    String version,
    Map<String, List<int>> payload,
  ) async {
    final root = _packageDir;
    if (root == null) {
      throw const AddonError.fetchFailed(
        'Armazenamento de pacotes indisponível.',
      );
    }
    final sep = Platform.pathSeparator;
    final versionDir = Directory('${root.path}$sep$id$sep$version');
    final tmp = Directory('${root.path}$sep.tmp-$id-'
        '$version-${DateTime.now().microsecondsSinceEpoch}');
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
      await tmp.create(recursive: true);
      for (final entry in payload.entries) {
        await File('${tmp.path}$sep${entry.key}')
            .writeAsBytes(entry.value);
      }
      if (await versionDir.exists()) {
        await versionDir.delete(recursive: true);
      }
      await versionDir.parent.create(recursive: true);
      await tmp.rename(versionDir.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      } catch (_) {}
      throw const AddonError.fetchFailed(
        'Não foi possível salvar os arquivos do pacote.',
      );
    }
    return versionDir;
  }

  /// Instala o pacote já validado, sempre desativado. Os arquivos
  /// vão para uma pasta temporária e só então para o lugar final;
  /// falha no meio não deixa pasta nem registro (T2).
  @override
  Future<AddonInfo> installPackage(
    AddonPackage package, {
    required bool originTrusted,
    AddonPackageOrigin packageOrigin = AddonPackageOrigin.file,
    String? sourceRepoId,
  }) async {
    if (!_allowUnknownSources() && !originTrusted) {
      throw const AddonError.unknownSourcesDisabled();
    }
    final manifest = package.manifest;
    if (_items.containsKey(manifest.id)) {
      throw const AddonError.alreadyInstalled();
    }
    final versionDir = await _writePackageDir(
      manifest.id,
      manifest.version,
      _payloadOf(package),
    );
    final info = AddonInfo(
      manifest: manifest,
      state: AddonState.inactive,
      originTrusted: originTrusted,
      installedAt: DateTime.now(),
      approvedOrigin: manifest.catalogUrl == null
          ? null
          : _hostOf(manifest.catalogUrl!),
      packageOrigin: packageOrigin,
      packageSha256: package.sha256,
      packageDir: versionDir.path,
      sourceRepoId: sourceRepoId,
    );
    _items[manifest.id] = info;
    _previous.remove(manifest.id);
    notifyListeners();
    await _save();
    return info;
  }

  /// Baixa o pacote anunciado e confere checksum, id e versao exata
  /// antes de tocar o disco: a recusa nao deixa pasta nem registro.
  Future<AddonPackage> _downloadVerifiedPackage(
    AddonManifest manifest, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    final packageUrl = manifest.packageUrl;
    final packageSha256 = manifest.packageSha256;
    if (packageUrl == null || packageSha256 == null) {
      throw const AddonError.invalidManifest(
        'Este item não tem pacote publicado para instalar.',
      );
    }
    final bytes = await _fetcher.fetchBytes(
      packageUrl,
      onProgress: onProgress,
      cancel: cancel,
    );
    if (sha256.convert(bytes).toString() != packageSha256) {
      throw const AddonError.invalidManifest(
        'Checksum do pacote não confere com o anunciado.',
      );
    }
    final package = await compute(readAddonPackage, bytes);
    if (package.manifest.id != manifest.id) {
      throw const AddonError.invalidManifest(
        'O pacote baixado não corresponde a este add-on.',
      );
    }
    if (AddonManifest.compareVersions(
            package.manifest.version, manifest.version) !=
        0) {
      throw AddonError.invalidManifest(
        'O pacote baixado não é a versão anunciada (${manifest.version}).',
      );
    }
    return package;
  }

  /// Pacote de repositorio (T4): baixa, confere e instala. O portao e
  /// o mesmo do pacote avulso; a conferencia (checksum/id/versao)
  /// acontece antes de tocar o disco de pacotes, entao a recusa nao
  /// deixa pasta nem registro.
  @override
  Future<AddonInfo> installPackageFromRepo(
    AddonManifest manifest, {
    required bool originTrusted,
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
    String? sourceRepoId,
  }) async {
    if (!_allowUnknownSources() && !originTrusted) {
      throw const AddonError.unknownSourcesDisabled();
    }
    final package = await _downloadVerifiedPackage(
      manifest,
      onProgress: onProgress,
      cancel: cancel,
    );
    return installPackage(
      package,
      originTrusted: originTrusted,
      packageOrigin: AddonPackageOrigin.repository,
      sourceRepoId: sourceRepoId,
    );
  }

  /// Catálogo embutido do pacote, ou null quando não há (legado ou
  /// reserva ausente). Nunca explode: falha vira isolamento no chamador.
  Future<List<AddonCatalogItem>?> _readEmbeddedCatalog(
      AddonInfo info) async {
    final dir = info.packageDir;
    if (dir == null) return null;
    try {
      final raw = await File(
              '$dir${Platform.pathSeparator}catalog.json')
          .readAsString();
      final items = parseCatalogItems(raw);
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  /// Apaga a árvore do add-on (<raiz>/<id>/), só dentro da raiz
  /// de pacotes. Falha de disco aqui não bloqueia a remoção.
  Future<void> _deletePackageTree(AddonInfo info) async {
    final dir = info.packageDir;
    if (dir == null) return;
    await _deleteTree(dir);
  }

  Future<void> _deleteTree(String versionDir) async {
    final root = _packageDir;
    if (root == null) return;
    try {
      final target = Directory(versionDir).parent;
      // Guarda com separador: prefixo puro aceitaria `<raiz>-evil`.
      if (!target.path.startsWith(
          '${root.path}${Platform.pathSeparator}')) {
        return;
      }
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _deletePackageRoot() async {
    final root = _packageDir;
    if (root == null) return;
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }

  @override
  Future<void> uninstall(String addonId) async {
    final info = _require(addonId);
    await _deletePackageTree(info);
    _items.remove(addonId);
    final backup = _previous.remove(addonId);
    final backupDir = backup?['packageDir'];
    if (backupDir is String) {
      await _deleteTree(backupDir);
    }
    notifyListeners();
    await _save();
  }

  @override
  Future<void> clearAllData() async {
    _items.clear();
    _repos.clear();
    _lastChange = null;
    _previous.clear();
    await _deletePackageRoot();
    notifyListeners();
    await _save();
    await _saveRepos();
  }

  @override
  Future<List<AddonManifest>> checkForUpdates() async {
    final found = <AddonManifest>[];
    var changed = false;
    for (final entry in _items.entries) {
      final available = await _fetchAvailable(entry.value);
      final wantFlag = available != null;
      if (entry.value.updateAvailable != wantFlag) {
        _items[entry.key] =
            entry.value.copyWith(updateAvailable: wantFlag);
        changed = true;
      }
      if (available != null) found.add(available);
    }
    if (changed) {
      notifyListeners();
      await _save();
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  /// Versao mais nova no updateUrl, ou null (sem updateUrl, adiada,
  /// falha de rede, manifesto invalido). O check nunca lanca.
  Future<AddonManifest?> _fetchAvailable(AddonInfo info) async {
    try {
      return await _fetchValidatedUpdate(info);
    } catch (_) {
      return null;
    }
  }

  /// Baixa e valida o manifesto do updateUrl: mesmo id, versao mais
  /// nova e nao adiada. Propaga [AddonError] com o motivo.
  Future<AddonManifest> _fetchValidatedUpdate(AddonInfo info) async {
    if (info.packageOrigin == AddonPackageOrigin.repository &&
        info.sourceRepoId != null) {
      return _fetchValidatedRepoUpdate(info);
    }
    final url = info.manifest.updateUrl;
    if (url == null) throw const AddonError.noUpdate();
    final manifest = await fetchManifest(url);
    if (manifest.id != info.manifest.id) {
      throw const AddonError.invalidManifest(
        'O manifesto de atualização não corresponde a este add-on.',
      );
    }
    if (AddonManifest.compareVersions(
            manifest.version, info.manifest.version) <=
        0) {
      throw const AddonError.noUpdate();
    }
    if (manifest.version == info.deferredVersion) {
      throw const AddonError.noUpdate();
    }
    return manifest;
  }

  /// Versao mais nova na listagem do repositorio de origem (T5):
  /// mesmo id, mais nova e nao adiada. Lanca no-update quando nao ha
  /// novidade (o check isola via [_fetchAvailable]); update e defer
  /// propagam o motivo.
  Future<AddonManifest> _fetchValidatedRepoUpdate(AddonInfo info) async {
    final repoId = info.sourceRepoId!;
    if (!_repos.containsKey(repoId)) throw const AddonError.noUpdate();
    AddonManifest? best;
    for (final manifest in await fetchRepoAddons(repoId)) {
      if (manifest.id != info.manifest.id) continue;
      if (best == null ||
          AddonManifest.compareVersions(manifest.version, best.version) >
              0) {
        best = manifest;
      }
    }
    final candidate = best;
    if (candidate == null) throw const AddonError.noUpdate();
    if (AddonManifest.compareVersions(
            candidate.version, info.manifest.version) <=
        0) {
      throw const AddonError.noUpdate();
    }
    if (candidate.version == info.deferredVersion) {
      throw const AddonError.noUpdate();
    }
    return candidate;
  }

  @override
  Future<AddonInfo> update(String addonId) async {
    final info = _require(addonId);
    final manifest = await _fetchValidatedUpdate(info);
    if (!manifest.supports(_platform)) {
      throw const AddonError.incompatible();
    }
    if (info.packageOrigin == AddonPackageOrigin.repository &&
        info.sourceRepoId != null) {
      return _updateToPackage(info, manifest);
    }
    // Backup integral (manifesto + estado) para o rollback. No
    // prototipo o add-on nao tem prefs proprias: o envelope e tudo
    // que ha para preservar.
    _previous[addonId] = info.toMap();
    _recordChange(info.manifest.id, info.manifest.name, 'update');
    final updated = _requireApprovalOfNewOrigin(info.copyWith(
      manifest: manifest,
      state: info.state == AddonState.error
          ? AddonState.inactive
          : info.state,
      updatedAt: () => DateTime.now(),
      diagnostic: () => null,
      updateAvailable: false,
      deferredVersion: () => null,
    ));
    await _update(updated);
    return updated;
  }

  /// A versao nova nao herda aprovacao de outro host: desativa e pede de
  /// novo, como na edicao de endereco. Sem feed, nao ha o que aprovar.
  AddonInfo _requireApprovalOfNewOrigin(AddonInfo updated) {
    if (_hostOf(updated.manifest.catalogUrl) == null) {
      return updated.copyWith(approvedOrigin: () => null);
    }
    if (!updated.needsApproval) return updated;
    return updated.copyWith(
      state: AddonState.inactive,
      diagnostic: () => approvalDiagnostic,
    );
  }

  /// Troca a versao instalada pelo pacote validado (T5): baixa e
  /// confere antes de mexer no instalado; a pasta anterior vira o
  /// backup e a mais antiga e apagada. Falha em qualquer ponto
  /// mantem a versao atual funcionando (nada foi trocado ainda ou a
  /// pasta nova e removida).
  Future<AddonInfo> _updateToPackage(
      AddonInfo info, AddonManifest manifest) async {
    final package = await _downloadVerifiedPackage(manifest);
    final versionDir = await _writePackageDir(
      info.manifest.id,
      manifest.version,
      _payloadOf(package),
    );
    try {
      await _rotatePackageBackup(info, manifest.version);
      _previous[info.manifest.id] = info.toMap();
      _recordChange(info.manifest.id, info.manifest.name, 'update');
      final updated = _requireApprovalOfNewOrigin(info.copyWith(
        manifest: manifest,
        state: info.state == AddonState.error
            ? AddonState.inactive
            : info.state,
        updatedAt: () => DateTime.now(),
        diagnostic: () => null,
        updateAvailable: false,
        deferredVersion: () => null,
        packageSha256: () => package.sha256,
        packageDir: () => versionDir.path,
      ));
      await _update(updated);
      return updated;
    } catch (_) {
      try {
        if (await versionDir.exists()) {
          await versionDir.delete(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Guarda a pasta atual como backup e apaga a mais antiga (T5):
  /// sob `<raiz>/<id>/` ficam so a versao nova e a anterior. O
  /// melhor esforco nunca bloqueia a atualizacao.
  Future<void> _rotatePackageBackup(AddonInfo info, String newVersion) async {
    final root = _packageDir;
    if (root == null) return;
    final sep = Platform.pathSeparator;
    final home = Directory('${root.path}$sep${info.manifest.id}');
    final nextPath = '${home.path}$sep$newVersion';
    final currentPath = info.packageDir;
    try {
      if (!await home.exists()) return;
      await for (final entity in home.list()) {
        if (entity is! Directory) continue;
        if (entity.path == nextPath) continue;
        if (currentPath != null && entity.path == currentPath) continue;
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Apaga so a pasta da versao, dentro da raiz de pacotes. Nada fora
  /// da raiz e tocado (espelha a guarda do `_deleteTree`).
  Future<void> _deleteVersionDir(String versionDir) async {
    final root = _packageDir;
    if (root == null) return;
    try {
      if (!versionDir.startsWith('${root.path}${Platform.pathSeparator}')) {
        return;
      }
      final dir = Directory(versionDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  @override
  Future<void> deferUpdate(String addonId) async {
    final info = _require(addonId);
    final manifest = await _fetchValidatedUpdate(info);
    await _update(info.copyWith(
      updateAvailable: false,
      deferredVersion: () => manifest.version,
    ));
  }

  @override
  Future<AddonInfo> rollback(String addonId) async {
    final info = _require(addonId);
    final raw = _previous[addonId];
    if (raw == null) throw const AddonError.noBackup();
    final restored = AddonInfo.fromMap(raw).copyWith(updateAvailable: true);
    _previous.remove(addonId);
    _items[restored.manifest.id] = restored;
    // Pacote (T5): a pasta da versao desfeita vira orfa; remove para
    // manter so atual + anterior. Nunca bloqueia o rollback.
    final currentDir = info.packageDir;
    if (currentDir != null && currentDir != restored.packageDir) {
      await _deleteVersionDir(currentDir);
    }
    notifyListeners();
    await _save();
    return restored;
  }

  @override
  String? previousVersion(String addonId) {
    final raw = _previous[addonId];
    final manifest = raw?['manifest'];
    if (manifest is! Map) return null;
    final version = manifest['version'];
    return version is String ? version : null;
  }

  Future<void> _update(AddonInfo info) async {
    _items[info.manifest.id] = info;
    notifyListeners();
    await _save();
  }

  @override
  Future<List<AddonCatalogItem>> getCatalog(String addonId) async {
    final info = _require(addonId);
    if (info.state != AddonState.active) return const [];
    try {
      if (_faultyIds.contains(info.manifest.id)) {
        throw StateError('defeito simulado no catalogo');
      }
      // Fase 5: manifesto com feed serve o catalogo remoto (validado
      // na borda, via adaptador da fonte quando houver); sem feed, o
      // catalogo embutido. Falha de rede ou corpo malformado isola o
      // add-on como qualquer defeito.
      final catalogUrl = info.manifest.catalogUrl;
      if (catalogUrl != null) {
        // await dentro do try: sem ele o erro escapa do isolamento.
        // Remoto tem prioridade; o embutido vira a reserva (T2).
        try {
          return await _loadRemoteCatalog(catalogUrl);
        } catch (_) {
          final embedded = await _readEmbeddedCatalog(info);
          if (embedded != null) return embedded;
          rethrow;
        }
      }
      final embedded = await _readEmbeddedCatalog(info);
      if (embedded != null) return embedded;
      if (info.packageDir != null) {
        throw const AddonError.fetchFailed(
          'Falha ao carregar o catálogo embutido.',
        );
      }
      return demoCatalog();
    } catch (_) {
      await _fail(
          info, 'Não foi possível carregar o catálogo deste add-on.');
      return const [];
    }
  }

  @override
  Future<List<AddonCatalogItem>> search(
      String addonId, String query) async {
    final info = _require(addonId);
    if (query.trim().isEmpty) return const [];
    if (info.state != AddonState.active) return const [];
    try {
      if (_faultyIds.contains(info.manifest.id)) {
        throw StateError('defeito simulado na busca');
      }
      final want = query.trim().toLowerCase();
      final catalogUrl = info.manifest.catalogUrl;
      // Busca no servidor quando o adaptador oferece; senao, filtro
      // local sobre o mesmo catalogo (remoto ou embutido).
      if (catalogUrl != null) {
        final adapter = SourceAdapters.forUrl(catalogUrl, _adapters);
        final target =
            adapter?.searchUrl(Uri.parse(catalogUrl), query.trim());
        if (adapter != null && target != null) {
          final headers = await adapter.headersFor(target, _credentials);
          final body = await _fetcher.fetchText(target.toString(),
              headers: headers);
          return adapter.parseCatalog(body).items;
        }
      }
      final catalog = catalogUrl != null
          ? await _loadRemoteCatalog(catalogUrl)
          : demoCatalog();
      return catalog
          .where((item) =>
              item.title.toLowerCase().contains(want) ||
              (item.subtitle?.toLowerCase().contains(want) ?? false))
          .toList();
    } catch (_) {
      await _fail(
          info, 'Não foi possível buscar neste add-on.');
      return const [];
    }
  }

  @override
  Future<MediaItem> resolvePlayback(
      String addonId, AddonCatalogItem item) async {
    final info = _require(addonId);
    if (info.state == AddonState.error) {
      throw const AddonError.unavailable();
    }
    if (info.state != AddonState.active) {
      throw const AddonError.disabled();
    }
    try {
      if (_faultyIds.contains(info.manifest.id)) {
        throw StateError('defeito simulado na resolucao');
      }
      return MediaItem(
        id: '${info.manifest.id}:${item.id}',
        title: item.title,
        subtitle: item.subtitle,
        sourceType: MediaSourceType.url,
        source: item.sourceUrl,
        duration: item.duration,
        addedAt: DateTime.now(),
        // Proveniencia para as informacoes do video (spec 26.12). O
        // titulo/subtitulo passam integros, sem traducao. Poster e
        // rendicoes passam como dados para a UI (cartao e menu de
        // qualidades usam quando houver).
        metadata: {
          'addonId': info.manifest.id,
          'addonName': info.manifest.name,
          if (item.thumbnailUrl != null) 'posterUrl': item.thumbnailUrl!,
          if (item.qualities.isNotEmpty)
            'qualities': encodeSourceQualities(item.qualities),
        },
      );
    } catch (_) {
      await _fail(info, 'Este add-on apresentou uma falha e foi isolado.');
      throw const AddonError.unavailable();
    }
  }

  /// Diagnostico padrao de origem pendente de aprovacao. Publico
  /// porque a UI compara para limpar so este diagnostico ao aprovar.
  static const approvalDiagnostic =
      'Endereço novo: aprove a origem nos detalhes para ativar.';

  static String? _hostOf(String? url) {
    if (url == null || url.isEmpty) return null;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? null : host.toLowerCase();
  }

  @override
  Future<SourcePreview> previewSource(String url) async {
    if (!_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    final trimmed = url.trim();
    // fetchText valida http/https e rede; lanca AddonError e nao
    // salva nada.
    final body = await _fetcher.fetchText(trimmed);
    try {
      return SourcePreview(
        manifest: AddonManifest.parseJson(body),
        feedItemCount: null,
      );
    } on AddonError {
      // Nao e manifesto: tenta feed (adaptador da fonte ou generico).
    }
    // Previa sem credenciais: fontes com auth obrigatoria ganham o
    // fluxo de credenciais na integracao real (5C).
    final adapter = SourceAdapters.forUrl(trimmed, _adapters);
    if (adapter != null) {
      try {
        final page = adapter.parseCatalog(body);
        final items = page.items;
        return SourcePreview(
          manifest: adapter.manifestFor(trimmed, items.length),
          feedItemCount: items.length,
          feedSample: items.take(5).map((item) => item.title).toList(),
        );
      } on AddonError {
        throw const AddonError.invalidManifest(
          'O endereço não é um manifesto nem um feed de catálogo válido.',
        );
      }
    }
    try {
      final items = parseCatalogItems(body);
      return SourcePreview(
        manifest: AddonManifest.fromFeed(url: trimmed, itemCount: items.length),
        feedItemCount: items.length,
        feedSample: items.take(5).map((item) => item.title).toList(),
      );
    } on AddonError {
      throw const AddonError.invalidManifest(
        'O endereço não é um manifesto nem um feed de catálogo válido.',
      );
    }
  }

  @override
  Future<AddonInfo> updateSourceUrl(String addonId, String newUrl) async {
    final info = _require(addonId);
    final trimmed = newUrl.trim();
    // Origem nova com o botão desligado nem chega a validar: falha
    // fechado antes de qualquer rede. Mesmo host segue o fluxo atual.
    final nextHost = _hostOf(trimmed);
    if (nextHost != null &&
        nextHost != info.approvedOrigin &&
        !_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    // Valida TUDO antes de salvar: URL, rede e feed parseavel (via
    // adaptador quando houver). O catalogo em si carrega sob demanda.
    await _loadRemoteCatalog(trimmed);
    final next =
        info.copyWith(manifest: info.manifest.withCatalogUrl(trimmed));
    if (next.needsApproval) {
      // Origem nova (ou primeiro feed): desativa e pede aprovacao,
      // mantendo a aprovacao antiga ate o usuario decidir.
      final updated = next.copyWith(
        state: AddonState.inactive,
        diagnostic: () => approvalDiagnostic,
      );
      await _update(updated);
      return updated;
    }
    await _update(next);
    return next;
  }

  @override
  Future<AddonInfo> approveSource(String addonId) async {
    final info = _require(addonId);
    final host = _hostOf(info.manifest.catalogUrl);
    if (host == null) return info;
    final updated = info.copyWith(
      approvedOrigin: () => host,
      // Limpa so o diagnostico de aprovacao; defeito real fica.
      diagnostic: () =>
          info.diagnostic == approvalDiagnostic ? null : info.diagnostic,
    );
    await _update(updated);
    return updated;
  }

  @override
  Future<int> refreshSource(String addonId) async {
    final info = _require(addonId);
    final catalogUrl = info.manifest.catalogUrl;
    if (catalogUrl == null) {
      throw const AddonError.fetchFailed('Esta fonte não tem feed remoto.');
    }
    try {
      return (await _loadRemoteCatalog(catalogUrl)).length;
    } catch (_) {
      await _fail(info, 'Não foi possível atualizar o catálogo desta fonte.');
      rethrow;
    }
  }

  /// Catalogo remoto com ou sem adaptador: formato da fonte
  /// quando alguma casa a URL, generico `{"items": [...]}` quando
  /// nenhuma casa. So lanca [AddonError] (rede, formato ou defeito
  /// do adaptador embrulhado); quem chama isola.
  Future<List<AddonCatalogItem>> _loadRemoteCatalog(String url) async {
    try {
      final adapter = SourceAdapters.forUrl(url, _adapters);
      if (adapter == null) {
        return parseCatalogItems(await _fetcher.fetchText(url));
      }
      final uri = Uri.parse(url);
      final headers = await adapter.headersFor(uri, _credentials);
      final body = await _fetcher.fetchText(url, headers: headers);
      return adapter.parseCatalog(body).items;
    } on AddonError {
      rethrow;
    } catch (_) {
      throw const AddonError.invalidManifest(
        'Catálogo inválido.',
      );
    }
  }

  /// Marca o add-on em erro com diagnostico legivel, sem afetar os
  /// demais (isolamento, §26.14).
  Future<void> _fail(AddonInfo info, String diagnostic) {
    return _update(info.copyWith(
      state: AddonState.error,
      diagnostic: () => diagnostic,
    ));
  }

  @override
  List<AddonRepository> get repositories {
    final list = _repos.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(list);
  }

  @override
  Future<AddonRepository> addRepository({
    required String name,
    required String originUrl,
    bool trusted = false,
  }) async {
    if (!_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    // Valida pela mesma porta de entrada dos dados externos: nada
    // digitado contorna as regras do modelo.
    final repo = AddonRepository.fromMap({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name.trim(),
      'originUrl': originUrl.trim(),
      'trusted': trusted,
      'addedAt': DateTime.now().toIso8601String(),
    });
    if (_repos.values.any((other) => other.originUrl == repo.originUrl)) {
      throw const AddonError.repoExists();
    }
    _repos[repo.id] = repo;
    notifyListeners();
    await _saveRepos();
    return repo;
  }

  @override
  Future<void> removeRepository(String repositoryId) async {
    if (!_repos.containsKey(repositoryId)) {
      throw const AddonError.repoNotFound();
    }
    _repos.remove(repositoryId);
    notifyListeners();
    await _saveRepos();
  }

  @override
  Future<List<AddonManifest>> fetchRepoAddons(String repositoryId) async {
    final repo = _repos[repositoryId];
    if (repo == null) throw const AddonError.repoNotFound();
    if (!repo.trusted && !_allowUnknownSources()) {
      throw const AddonError.unknownSourcesDisabled();
    }
    return AddonRepository.parseListing(
      await _fetcher.fetchText(repo.originUrl),
    );
  }
}
