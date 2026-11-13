import 'package:flutter/foundation.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/addon_service.dart';

/// Add-ons com fileira no Início (T8): ativos e com erro (a fileira
/// mostra o erro e o "Tentar de novo"). Inativo não aparece. Destino
/// escondido e modo seguro não têm fileira nenhuma.
List<AddonInfo> homeAddonRowInfos(
  List<AddonInfo> addons, {
  List<MainDestination> hidden = const [],
  bool safeMode = false,
}) {
  if (safeMode || hidden.contains(MainDestination.addons)) return const [];
  return [
    for (final info in addons)
      if (info.state != AddonState.inactive) info,
  ];
}

/// Estado de uma fileira: carregando, itens ou erro.
class HomeAddonRowState {
  const HomeAddonRowState({
    this.loading = false,
    this.loaded = false,
    this.items = const [],
    this.error,
  });

  final bool loading;

  /// Já houve uma resposta: fileira vazia depois disso some.
  final bool loaded;
  final List<AddonCatalogItem> items;
  final String? error;
}

/// Catálogos das fileiras, guardados em memória enquanto o Início vive:
/// abrir o app de novo busca de novo; voltar do player não. Cada add-on
/// carrega sozinho, e a falha de um não toca nos outros.
class HomeAddonRows extends ChangeNotifier {
  HomeAddonRows(
    this._addons, {
    List<MainDestination> Function()? hidden,
    bool Function()? safeMode,
  })  : _hidden = hidden ?? (() => const []),
        _safeMode = safeMode ?? (() => false) {
    _addons.addListener(reconcile);
  }

  static const maxItems = 20;

  final AddonService _addons;
  final List<MainDestination> Function() _hidden;
  final bool Function() _safeMode;
  final _states = <String, HomeAddonRowState>{};

  /// Versão, feed e pacote de cada catálogo guardado: atualizar o
  /// add-on ou trocar o endereço invalida o que estava em memória.
  final _signatures = <String, String>{};
  final _inFlight = <String, Future<void>>{};

  /// Add-ons que já foram à rede desde que o app abriu. Erro salvo por uma
  /// sessão anterior ganha uma tentativa sozinho: queda passageira de rede
  /// não fica marcada como defeito. Falha desta sessão espera o usuário.
  final _attempted = <String>{};
  bool _disposed = false;

  List<AddonInfo> get infos => homeAddonRowInfos(
        _addons.addons,
        hidden: _hidden(),
        safeMode: _safeMode(),
      );

  HomeAddonRowState stateOf(String addonId) =>
      _states[addonId] ?? const HomeAddonRowState();

  /// Fileiras com algo a mostrar: catálogo vazio já respondido some.
  List<AddonInfo> get visibleInfos {
    return [
      for (final info in infos)
        if (!_isEmptyAnswer(stateOf(info.manifest.id))) info,
    ];
  }

  bool _isEmptyAnswer(HomeAddonRowState state) =>
      state.loaded &&
      !state.loading &&
      state.items.isEmpty &&
      state.error == null;

  static String _signatureOf(AddonInfo info) => [
        info.manifest.version,
        info.manifest.catalogUrl ?? '',
        info.packageDir ?? '',
      ].join('|');

  /// Acerta as fileiras com os add-ons de agora. Só busca o que falta:
  /// chamar de novo não repete a rede.
  void reconcile() {
    if (_disposed) return;
    final current = infos;
    final ids = {for (final info in current) info.manifest.id};
    final dropped = _states.keys.where((id) => !ids.contains(id)).toList();
    for (final id in dropped) {
      _states.remove(id);
      _signatures.remove(id);
    }
    var changed = dropped.isNotEmpty;
    for (final info in current) {
      final id = info.manifest.id;
      final state = _states[id];
      final signature = _signatureOf(info);
      if (state?.loading ?? false) continue;
      if (info.state == AddonState.error) {
        if (_attempted.add(id)) {
          // A saída do erro avisa os ouvintes e este método busca.
          _addons.clearError(id);
          continue;
        }
        // Já tentou: mostra o motivo sem ir à rede.
        if (state?.error != _message(info)) {
          _states[id] = HomeAddonRowState(
            loaded: true,
            items: state?.items ?? const [],
            error: _message(info),
          );
          changed = true;
        }
        continue;
      }
      if (state == null ||
          state.error != null ||
          _signatures[id] != signature) {
        _start(info, signature);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Busca de novo as fileiras que sumiram por catálogo vazio: o feed pode
  /// ter ganhado itens desde a resposta. Chamado ao voltar ao app.
  void refreshEmpty() {
    if (_disposed) return;
    var changed = false;
    for (final info in infos) {
      final id = info.manifest.id;
      if (info.state != AddonState.error && _isEmptyAnswer(stateOf(id))) {
        _start(info, _signatureOf(info));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// "Atualizar": busca de novo, mantendo os itens até a resposta.
  Future<void> refresh(String addonId) async {
    final info = _addons.findById(addonId);
    if (info == null || stateOf(addonId).loading) return;
    // Em erro o catálogo não busca nada: atualizar é tentar de novo.
    if (info.state == AddonState.error) return retry(addonId);
    final loading = _start(info, _signatureOf(info));
    notifyListeners();
    await loading;
  }

  /// "Tentar de novo": tira o add-on do erro e busca. Se ele não puder
  /// sair do erro (origem pendente, plataforma), a fileira mostra o motivo.
  Future<void> retry(String addonId) async {
    if (_addons.findById(addonId) == null) return;
    await _addons.clearError(addonId);
    await _inFlight[addonId];
  }

  Future<void> _start(AddonInfo info, String signature) {
    final id = info.manifest.id;
    _attempted.add(id);
    _signatures[id] = signature;
    _states[id] = HomeAddonRowState(
      loading: true,
      loaded: _states[id]?.loaded ?? false,
      items: _states[id]?.items ?? const [],
    );
    return _inFlight[id] = _load(id);
  }

  Future<void> _load(String id) async {
    List<AddonCatalogItem> items;
    try {
      items = await _addons.getCatalog(id);
    } catch (_) {
      items = const [];
    }
    _inFlight.remove(id);
    if (_disposed) return;
    final after = _addons.findById(id);
    if (after == null || after.state == AddonState.inactive) {
      _states.remove(id);
      _signatures.remove(id);
    } else if (after.state == AddonState.error) {
      _states[id] = HomeAddonRowState(loaded: true, error: _message(after));
    } else {
      _states[id] = HomeAddonRowState(
        loaded: true,
        items: items.take(maxItems).toList(growable: false),
      );
    }
    notifyListeners();
    // O add-on pode ter mudado durante a busca.
    reconcile();
  }

  static String _message(AddonInfo info) =>
      info.diagnostic ?? 'Não foi possível carregar o catálogo deste add-on.';

  @override
  void dispose() {
    _disposed = true;
    _addons.removeListener(reconcile);
    super.dispose();
  }
}
