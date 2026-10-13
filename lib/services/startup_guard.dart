import 'package:flutter/foundation.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/local_addon_service.dart';

/// Motivo do modo seguro: falhas repetidas ou escolha manual.
enum SafeModeReason { crashes, manual }

/// Guarda de arranque e modo seguro (spec 6.1, Fase 5). Conta arranques
/// nao concluidos: a partir de 2 falhas seguidas, o app abre em modo
/// seguro (sem carregar add-ons). Um arranque limpo zera o contador.
/// Tambem guarda o ultimo erro capturado e oferece desativar a ultima
/// alteracao de add-on direto no documento persistido (o servico nao
/// e carregado em modo seguro, entao nao ha por onde chamar).
class StartupGuard extends ChangeNotifier {
  StartupGuard(this._store);

  final LocalStore _store;

  static const _key = 'startup_guard';

  /// Falhas seguidas a partir das quais o modo seguro engata.
  static const crashThreshold = 2;

  int _pendingBoots = 0;

  /// Falhas observadas ANTES deste arranque. Congelado no [beginBoot]:
  /// e ele que decide o modo seguro da sessao (o contador segue
  /// contando este arranque como pendente ate o [markCleanBoot]).
  int _bootFailures = 0;
  bool _manualSafeMode = false;
  Map<String, Object?>? _lastError;

  /// Falhas seguidas observadas (para a faixa e o diagnostico).
  int get consecutiveFailures => _bootFailures;

  bool get manualSafeMode => _manualSafeMode;

  bool get safeMode => _manualSafeMode || _bootFailures >= crashThreshold;

  SafeModeReason? get safeModeReason {
    if (_manualSafeMode) return SafeModeReason.manual;
    if (_bootFailures >= crashThreshold) return SafeModeReason.crashes;
    return null;
  }

  Map<String, Object?>? get lastError =>
      _lastError == null ? null : Map.unmodifiable(_lastError!);

  /// Inicio do arranque: le o estado, decide o modo seguro e registra
  /// este arranque como pendente. Chamar uma vez no [main], antes do
  /// [runApp]. A checagem usa o valor ARMAZENADO: sao preciso 2
  /// arranques sujos observados antes de engatar.
  Future<void> beginBoot() async {
    await _load();
    _bootFailures = _pendingBoots;
    _pendingBoots += 1;
    await _save();
    notifyListeners();
  }

  /// Arranque concluido (primeiro frame): zera as falhas. Chamar uma
  /// vez, via post-frame callback no [main].
  Future<void> markCleanBoot() async {
    _pendingBoots = 0;
    await _save();
    notifyListeners();
  }

  /// Liga/desliga o modo seguro manual (tela de diagnostico). Vale a
  /// partir do proximo arranque para a carga de add-ons.
  Future<void> setManualSafeMode(bool value) async {
    _manualSafeMode = value;
    await _save();
    notifyListeners();
  }

  /// Registra um erro capturado (zona ou FlutterError). Mensagem e
  /// pilha truncadas: erros podem carregar caminhos e URLs (spec 6.1:
  /// sem dados sensiveis). A pilha (4 primeiras linhas) identifica o
  /// ponto exato sem vazar o resto. URLs, caminhos e credenciais
  /// viram marcadores antes de persistir (spec 6.1).
  static final _urlPattern = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+');
  static final _windowsPathPattern = RegExp(r'[A-Za-z]:\\\S*');
  static final _unixPathPattern = RegExp(r'(?<![\w:])/(?:[\w.\-]+/)+[\w.\-]*');
  static final _credentialPattern = RegExp(
      r'(token|key|sig|secret|password|passwd|auth|session)=([^\s&;]+)',
      caseSensitive: false);

  static String sanitizeErrorText(String text) {
    var out = text.replaceAll(_urlPattern, '[url]');
    out = out.replaceAll(_windowsPathPattern, '[caminho]');
    out = out.replaceAll(_unixPathPattern, '[caminho]');
    out = out.replaceAllMapped(
        _credentialPattern, (m) => '${m.group(1)}=[credencial]');
    return out;
  }

  Future<void> recordError(Object error, [StackTrace? stack]) async {
    final rawMessage = error.toString();
    final message = sanitizeErrorText(rawMessage);
    final rawTrace = stack?.toString() ?? '';
    final trace =
        sanitizeErrorText(rawTrace.split('\n').take(4).join('\n'));
    _lastError = {
      'at': DateTime.now().toIso8601String(),
      'message': message.length > 200 ? message.substring(0, 200) : message,
      'kind': classifyPlaybackError(rawMessage).name,
      if (trace.isNotEmpty)
        'stack': trace.length > 300 ? trace.substring(0, 300) : trace,
    };
    await _save();
    notifyListeners();
  }

  /// Ultima alteracao de add-on registrada (instalacao/ativacao), lida
  /// direto do documento persistido. Null quando nao ha.
  Future<LastAddonChange?> readLastChange() async {
    final doc = await _store.read(LocalAddonService.storeKey);
    final raw = doc?['lastChange'];
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final id = map['id'];
    final name = map['name'];
    if (id is! String || name is! String) return null;
    return LastAddonChange(id: id, name: name);
  }

  /// Desativa a ultima alteracao direto no documento persistido.
  /// Devolve false quando nao havia nada a desativar. Consome o
  /// registro para a acao nao se repetir.
  Future<bool> disableLastChange() async {
    final doc = await _store.read(LocalAddonService.storeKey);
    if (doc == null) return false;
    final rawChange = doc['lastChange'];
    final rawItems = doc['items'];
    if (rawChange is! Map || rawItems is! List) return false;
    final id = rawChange['id'];
    var disabled = false;
    final items = <Object?>[];
    for (final raw in rawItems) {
      if (raw is Map &&
          (raw['manifest'] is Map) &&
          ((raw['manifest'] as Map)['id'] == id)) {
        final entry = Map<String, Object?>.from(raw);
        entry['state'] = 'inactive';
        entry['diagnostic'] = null;
        items.add(entry);
        disabled = true;
      } else {
        items.add(raw);
      }
    }
    if (!disabled) return false;
    await _store.write(LocalAddonService.storeKey, {
      'items': items,
      'lastChange': null,
    });
    notifyListeners();
    return true;
  }

  /// Limpa registros efemeros (ultimo erro). Acao "limpar cache" do
  /// diagnostico: o app nao acumula cache de midia nesta versao.
  Future<void> clearEphemeral() async {
    _lastError = null;
    await _save();
    notifyListeners();
  }

  /// Apaga todo o estado de recuperacao (acao "limpar dados do app").
  Future<void> clearRecoveryData() async {
    _pendingBoots = 0;
    _bootFailures = 0;
    _manualSafeMode = false;
    _lastError = null;
    try {
      await _store.remove(_key);
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final doc = await _store.read(_key);
      _pendingBoots = (doc?['pendingBoots'] as int?) ?? 0;
      _manualSafeMode = (doc?['manualSafeMode'] as bool?) ?? false;
      final rawError = doc?['lastError'];
      _lastError =
          rawError is Map ? Map<String, Object?>.from(rawError) : null;
    } catch (_) {
      _pendingBoots = 0;
      _manualSafeMode = false;
      _lastError = null;
    }
  }

  Future<void> _save() async {
    try {
      await _store.write(_key, {
        'pendingBoots': _pendingBoots,
        'manualSafeMode': _manualSafeMode,
        'lastError': _lastError,
      });
    } catch (_) {
      // Falha de persistencia nao interrompe o uso (spec 19).
    }
  }
}

/// Ultima alteracao de add-on: o que a faixa de modo seguro oferece
/// desativar.
class LastAddonChange {
  const LastAddonChange({required this.id, required this.name});

  final String id;
  final String name;
}
