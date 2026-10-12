import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/addon_fetcher.dart';
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
  })  : _platform = platform ?? Platform.operatingSystem,
        _faultyIds = faultyIds ?? const {},
        _fetcher = fetcher,
        _adapters = adapters,
        _credentials = credentials ?? InMemoryCredentialStore();

  final LocalStore _store;
  final AddonFetcher _fetcher;

  /// Adaptadores por fonte (5C). Vazio = so o formato generico
  /// `{"items": [...]}`; cada URL casa no maximo um adaptador.
  final List<SourceAdapter> _adapters;
  final SourceCredentialStore _credentials;
  final String _platform;

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
    if (_items.containsKey(manifest.id)) {
      throw const AddonError.alreadyInstalled();
    }
    final info = AddonInfo(
      manifest: manifest,
      originTrusted: originTrusted,
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
  Future<void> disable(String addonId) async {
    final info = _require(addonId);
    await _update(info.copyWith(
      state: AddonState.inactive,
      diagnostic: () => null,
    ));
  }

  @override
  Future<void> uninstall(String addonId) async {
    _require(addonId);
    _items.remove(addonId);
    _previous.remove(addonId);
    notifyListeners();
    await _save();
  }

  @override
  Future<void> clearAllData() async {
    _items.clear();
    _repos.clear();
    _lastChange = null;
    _previous.clear();
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

  @override
  Future<AddonInfo> update(String addonId) async {
    final info = _require(addonId);
    final manifest = await _fetchValidatedUpdate(info);
    if (!manifest.supports(_platform)) {
      throw const AddonError.incompatible();
    }
    // Backup integral (manifesto + estado) para o rollback. No
    // prototipo o add-on nao tem prefs proprias: o envelope e tudo
    // que ha para preservar.
    _previous[addonId] = info.toMap();
    _recordChange(info.manifest.id, info.manifest.name, 'update');
    final updated = info.copyWith(
      manifest: manifest,
      state: info.state == AddonState.error
          ? AddonState.inactive
          : info.state,
      updatedAt: () => DateTime.now(),
      diagnostic: () => null,
      updateAvailable: false,
      deferredVersion: () => null,
    );
    await _update(updated);
    return updated;
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
    _require(addonId);
    final raw = _previous[addonId];
    if (raw == null) throw const AddonError.noBackup();
    final restored = AddonInfo.fromMap(raw).copyWith(updateAvailable: true);
    _previous.remove(addonId);
    _items[restored.manifest.id] = restored;
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
        return await _loadRemoteCatalog(catalogUrl);
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
    return AddonRepository.parseListing(
      await _fetcher.fetchText(repo.originUrl),
    );
  }
}
