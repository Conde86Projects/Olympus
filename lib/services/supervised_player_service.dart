import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_permission_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/playback_watchdog.dart';

/// Entrada do log tecnico: etapa + instante + duracao + desfecho. Nunca
/// carrega titulo, caminho, URL ou mensagem nativa (spec 6.1: sem dados
/// sensiveis).
class PlaybackLogEntry {
  const PlaybackLogEntry({
    required this.stage,
    required this.at,
    this.durationMs,
    this.outcome,
  });

  final String stage;
  final DateTime at;
  final int? durationMs;
  final String? outcome;

  @override
  String toString() =>
      'PlaybackLogEntry($stage@${at.toIso8601String()}'
      '${durationMs == null ? '' : ' ${durationMs}ms'}'
      '${outcome == null ? '' : ' $outcome'})';
}

/// Supervisor de reproducao (spec 26): decora qualquer
/// [MediaPlayerService] com pre-checagem de arquivo local, timeout de
/// carga e de buffer, liberacao da sessao anterior, classificacao de
/// erros e log tecnico. Toda falha vira sessao de erro RECUPERAVEL: o
/// [open] nunca lanca (a UI nao envolve a abertura em try/catch).
/// Timeout e testavel: os prazos entram pelo construtor.
class SupervisedPlayerService implements MediaPlayerService {
  SupervisedPlayerService(
    this._inner, {
    this.loadTimeout = AppConstants.loadTimeout,
    this.bufferTimeout = AppConstants.bufferTimeout,
    Future<bool> Function()? hasMediaAccess,
    Future<bool> Function(String path)? canReadFile,
  })  : _hasMediaAccess =
            hasMediaAccess ?? (() => const MediaPermissionService().hasAccess),
        _canReadFile = canReadFile ?? _defaultCanReadFile {
    _watchdog = PlaybackWatchdog(
      loadTimeout: loadTimeout,
      bufferTimeout: bufferTimeout,
      current: () => _mirror,
      onExpired: (event) {
        _logEvent(event, outcome: 'fired');
        _fail(PlaybackErrorKind.timeout, _generation);
      },
    );
    _subscription = _inner.sessionStream.listen(_onInner);
  }

  final MediaPlayerService _inner;
  final Future<bool> Function() _hasMediaAccess;
  final Future<bool> Function(String path) _canReadFile;

  /// O arquivo existe e da para abrir para leitura (le 1 byte).
  static Future<bool> _defaultCanReadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      await file.openRead(0, 1).drain<void>();
      return true;
    } catch (_) {
      return false;
    }
  }
  bool _openingLocal = false;
  String _openingPath = '';
  final Duration loadTimeout;
  final Duration bufferTimeout;

  static const maxLogEntries = 50;

  final _sessionController = StreamController<PlaybackSession>.broadcast();
  late final StreamSubscription<PlaybackSession> _subscription;

  PlaybackSession _mirror = const PlaybackSession();
  final List<PlaybackLogEntry> _log = [];

  late final PlaybackWatchdog _watchdog;
  int _generation = 0;

  /// Erro injetado pelo supervisor (pre-checagem/timeout): segura o
  /// espelho ate a proxima abertura, parada ou sinal de vida do motor.
  PlaybackSession? _latched;
  PlaybackStatus? _latchedFrom;

  DateTime? _openStartedAt;

  /// Log tecnico (leitura). Mais recentes por ultimo.
  List<PlaybackLogEntry> get techLog => List.unmodifiable(_log);

  @override
  PlaybackSession get session => _mirror;

  @override
  Stream<PlaybackSession> get sessionStream => _sessionController.stream;

  @override
  Widget buildVideoView() => _inner.buildVideoView();

  @override
  Future<void> open(MediaItem item) async {
    final generation = ++_generation;
    _watchdog.cancel();
    _latched = null;
    _openStartedAt = DateTime.now();
    _openingLocal = item.sourceType == MediaSourceType.local;
    _openingPath = item.source;

    if (item.sourceType == MediaSourceType.local &&
        !await File(item.source).exists()) {
      _logEvent('precheck', outcome: 'missing');
      try {
        // Sem isso a midia anterior seguiria tocando sob o overlay.
        await _inner.stop();
      } catch (_) {
        // Parada best-effort: o erro segue.
      }
      // No Android recente, sem permissao de midia o sistema esconde o
      // arquivo e exists() devolve false: sem acesso o erro e de
      // permissao, nao de arquivo ausente.
      var hasAccess = true;
      try {
        hasAccess = await _hasMediaAccess();
      } catch (_) {
        // Sem resposta da plataforma: trata como arquivo ausente.
      }
      _fail(
        hasAccess ? PlaybackErrorKind.source : PlaybackErrorKind.permission,
        generation,
      );
      return;
    }
    _logEvent('precheck', outcome: 'ok');

    // Libera a sessao anterior antes de abrir (spec 26): o espelho
    // zera na hora e o motor e parado antes do novo open.
    _mirror = PlaybackSession(
      mediaId: item.id,
      status: PlaybackStatus.loading,
      volume: _mirror.volume,
      isMuted: _mirror.isMuted,
      speed: _mirror.speed,
    );
    _emit();
    try {
      await _inner.stop();
    } catch (_) {
      // Parada best-effort: a abertura segue.
    }
    try {
      await _inner.open(item).timeout(loadTimeout);
    } on TimeoutException {
      _logEvent('open', outcome: 'timeout');
      _fail(PlaybackErrorKind.timeout, generation);
      return;
    } catch (error) {
      var kind = classifyPlaybackError(error.toString());
      if (item.sourceType == MediaSourceType.local && _maskedPermission(kind)) {
        kind = await _refineLocalError(kind, item.source);
      }
      _logEvent('open', outcome: kind.name);
      _fail(kind, generation);
      return;
    }
    _logEvent('open', outcome: 'started');
    if (generation == _generation) _watchdog.armLoad();
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> stop() async {
    _generation++;
    _watchdog.cancel();
    _latched = null;
    try {
      await _inner.stop();
    } catch (_) {
      // Parada best-effort: o espelho zera de todo jeito.
    }
    _mirror = PlaybackSession(
      volume: _mirror.volume,
      isMuted: _mirror.isMuted,
      speed: _mirror.speed,
    );
    _logEvent('stop');
    _emit();
  }

  @override
  Future<void> seek(Duration position) => _inner.seek(position);

  @override
  Future<void> seekBy(Duration offset) => _inner.seekBy(offset);

  @override
  Future<void> setVolume(double value) => _inner.setVolume(value);

  @override
  Future<void> setMuted(bool muted) => _inner.setMuted(muted);

  @override
  Future<void> setSpeed(double value) => _inner.setSpeed(value);

  @override
  Future<void> selectAudio(String trackId) => _inner.selectAudio(trackId);

  @override
  Future<void> selectSubtitle(String? trackId) =>
      _inner.selectSubtitle(trackId);

  @override
  Future<void> addExternalSubtitle(String path) =>
      _inner.addExternalSubtitle(path);

  @override
  Future<void> selectVideo(String? trackId) => _inner.selectVideo(trackId);

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      _inner.setRepeatMode(mode);

  @override
  Future<void> rotateClockwise() => _inner.rotateClockwise();

  @override
  Future<void> rotateCounterClockwise() => _inner.rotateCounterClockwise();

  @override
  Future<void> dispose() async {
    _generation++;
    _watchdog.cancel();
    await _subscription.cancel();
    await _sessionController.close();
    await _inner.dispose();
  }

  void _onInner(PlaybackSession session) {
    if (_latched != null &&
        (session.status != _latchedFrom || _startedAfterStall(session))) {
      // Sinal de vida depois do erro injetado: o motor se recuperou
      // sozinho, o espelho volta a segui-lo.
      _latched = null;
      _latchedFrom = null;
    }
    if (_latched != null) return;
    if (session.status == PlaybackStatus.error) {
      final kind = classifyPlaybackError(session.errorMessage);
      if (_openingLocal && _maskedPermission(kind)) {
        // Decide depois de consultar o acesso aos arquivos.
        final generation = _generation;
        final path = _openingPath;
        unawaited(() async {
          final refined = await _refineLocalError(kind, path);
          if (generation != _generation || _latched != null) return;
          _applyInner(session, refined);
        }());
        return;
      }
      _applyInner(session, kind);
      return;
    }
    _applyInner(session, null);
  }

  void _applyInner(PlaybackSession session, PlaybackErrorKind? kind) {
    var mirror = session;
    if (kind != null) {
      mirror = session.copyWith(errorKind: () => kind);
      _logEvent('error', outcome: kind.name);
    }
    _mirror = mirror;
    _watchdog.observe(mirror);
    _emit();
  }

  /// Tipos que o motor usa quando o Android esconde o arquivo por falta
  /// de permissao: "Failed to open" sem "permission denied".
  bool _maskedPermission(PlaybackErrorKind kind) =>
      kind == PlaybackErrorKind.network ||
      kind == PlaybackErrorKind.source ||
      kind == PlaybackErrorKind.unknown;

  /// Em arquivo local, sem acesso aos arquivos o erro e de permissao, mas
  /// so quando o arquivo NAO e legivel: se da para ler (ex.: copia do
  /// seletor no cache do app), o tipo segue como o motor classificou.
  Future<PlaybackErrorKind> _refineLocalError(
      PlaybackErrorKind kind, String path) async {
    try {
      if (!await _hasMediaAccess() && !await _canReadFile(path)) {
        return PlaybackErrorKind.permission;
      }
    } catch (_) {
      // Sem resposta da plataforma: mantem o tipo classificado.
    }
    return kind;
  }

  /// Vigia tocando no zero disparou, mas o video enfim avancou.
  bool _startedAfterStall(PlaybackSession session) =>
      _latchedFrom == PlaybackStatus.playing &&
      session.status == PlaybackStatus.playing &&
      !PlaybackWatchdog.isStalledAtStart(session);

  /// Erro do supervisor: trava o espelho ate a proxima abertura, parada
  /// ou sinal de vida do motor. Timer de geracao antiga e ignorado.
  void _fail(PlaybackErrorKind kind, int generation) {
    if (generation != _generation) return;
    _watchdog.cancel();
    _latchedFrom = _mirror.status;
    _latched = _mirror = _mirror.copyWith(
      status: PlaybackStatus.error,
      position: Duration.zero,
      duration: () => null,
      errorKind: () => kind,
      errorMessage: () => null,
    );
    _logEvent('error', outcome: kind.name);
    _emit();
  }

  /// Sonda de diagnostico da retomada HLS (instrumentacao, sem
  /// efeito funcional): registra etapa + detalhe numerico no log
  /// tecnico local. [detail] so pode conter numeros, estados, o id
  /// do item e o rotulo da variante — nunca URL, caminho, token ou
  /// mensagem nativa do motor.
  void logResumeProbe(String stage, {String? detail}) {
    _log.add(PlaybackLogEntry(
      stage: 'resume-$stage',
      at: DateTime.now(),
      outcome: detail,
    ));
    while (_log.length > maxLogEntries) {
      _log.removeAt(0);
    }
  }

  void _logEvent(String stage, {String? outcome}) {
    final started = _openStartedAt;
    _log.add(PlaybackLogEntry(
      stage: stage,
      at: DateTime.now(),
      durationMs: started == null
          ? null
          : DateTime.now().difference(started).inMilliseconds,
      outcome: outcome,
    ));
    while (_log.length > maxLogEntries) {
      _log.removeAt(0);
    }
  }

  void _emit() {
    if (!_sessionController.isClosed) _sessionController.add(_mirror);
  }
}
