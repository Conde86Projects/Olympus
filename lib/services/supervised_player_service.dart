import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';

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
  }) {
    _subscription = _inner.sessionStream.listen(_onInner);
  }

  final MediaPlayerService _inner;
  final Duration loadTimeout;
  final Duration bufferTimeout;

  static const maxLogEntries = 50;

  final _sessionController = StreamController<PlaybackSession>.broadcast();
  late final StreamSubscription<PlaybackSession> _subscription;

  PlaybackSession _mirror = const PlaybackSession();
  final List<PlaybackLogEntry> _log = [];

  Timer? _loadTimer;
  Timer? _bufferTimer;
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
    _cancelTimers();
    _latched = null;
    _openStartedAt = DateTime.now();

    if (item.sourceType == MediaSourceType.local &&
        !await File(item.source).exists()) {
      _logEvent('precheck', outcome: 'missing');
      try {
        // Sem isso a midia anterior seguiria tocando sob o overlay.
        await _inner.stop();
      } catch (_) {
        // Parada best-effort: o erro segue.
      }
      _fail(PlaybackErrorKind.source, generation);
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
      final kind = classifyPlaybackError(error.toString());
      _logEvent('open', outcome: kind.name);
      _fail(kind, generation);
      return;
    }
    _logEvent('open', outcome: 'started');
    _armLoadTimer(generation);
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> stop() async {
    _generation++;
    _cancelTimers();
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
    _cancelTimers();
    await _subscription.cancel();
    await _sessionController.close();
    await _inner.dispose();
  }

  void _onInner(PlaybackSession session) {
    if (_latched != null && session.status != _latchedFrom) {
      // Sinal de vida depois do erro injetado: o motor se recuperou
      // sozinho, o espelho volta a segui-lo.
      _latched = null;
      _latchedFrom = null;
    }
    if (_latched != null) return;
    var mirror = session;
    if (session.status == PlaybackStatus.error) {
      final kind = classifyPlaybackError(session.errorMessage);
      mirror = session.copyWith(errorKind: () => kind);
      _logEvent('error', outcome: kind.name);
    }
    _mirror = mirror;
    _retime(mirror.status);
    _emit();
  }

  /// Erro do supervisor: trava o espelho ate a proxima abertura, parada
  /// ou sinal de vida do motor. Timer de geracao antiga e ignorado.
  void _fail(PlaybackErrorKind kind, int generation) {
    if (generation != _generation) return;
    _cancelTimers();
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

  void _armLoadTimer(int generation) {
    _loadTimer?.cancel();
    _loadTimer = Timer(loadTimeout, () {
      if (generation != _generation) return;
      if (_mirror.status != PlaybackStatus.loading) return;
      _logEvent('timeout-load', outcome: 'fired');
      _fail(PlaybackErrorKind.timeout, generation);
    });
  }

  void _retime(PlaybackStatus status) {
    if (status != PlaybackStatus.loading) _loadTimer?.cancel();
    if (status == PlaybackStatus.buffering && _bufferTimer == null) {
      final generation = _generation;
      _bufferTimer = Timer(bufferTimeout, () {
        _bufferTimer = null;
        if (generation != _generation) return;
        if (_mirror.status != PlaybackStatus.buffering) return;
        _logEvent('timeout-buffer', outcome: 'fired');
        _fail(PlaybackErrorKind.timeout, generation);
      });
    } else if (status != PlaybackStatus.buffering) {
      _bufferTimer?.cancel();
      _bufferTimer = null;
    }
  }

  void _cancelTimers() {
    _loadTimer?.cancel();
    _loadTimer = null;
    _bufferTimer?.cancel();
    _bufferTimer = null;
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
