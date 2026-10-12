import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';

/// Implementacao real do contrato de reproducao sobre media_kit/libmpv
/// (Fase 2). Exige [MediaKit.ensureInitialized] antes de instanciar (feito
/// no `main`). Nao usar em `flutter test`: o mpv nativo nao existe no
/// testador — os testes usam [NoOpMediaPlayerService].
class MediaKitPlayerService implements MediaPlayerService {
  MediaKitPlayerService() {
    _videoController = VideoController(_player);
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        _playing = playing;
        _emit();
      }),
      _player.stream.completed.listen((completed) {
        _completed = completed;
        _emit();
      }),
      _player.stream.position.listen((position) {
        _position = position;
        _emit();
      }),
      _player.stream.duration.listen((duration) {
        _duration = duration;
        _emit();
      }),
      _player.stream.volume.listen((volume) {
        _volume = (volume / 100).clamp(0.0, 1.0);
        if (volume > 0) _muted = false;
        _emit();
      }),
      _player.stream.rate.listen((rate) {
        _rate = rate;
        _emit();
      }),
      _player.stream.buffering.listen((buffering) {
        _buffering = buffering;
        _emit();
      }),
      _player.stream.tracks.listen((tracks) {
        _tracks = tracks;
        _emit();
      }),
      _player.stream.track.listen((track) {
        _track = track;
        _emit();
      }),
      _player.stream.playlistMode.listen((mode) {
        _repeatMode = switch (mode) {
          PlaylistMode.single => PlaybackRepeatMode.one,
          PlaylistMode.loop => PlaybackRepeatMode.all,
          PlaylistMode.none => PlaybackRepeatMode.off,
        };
        _emit();
      }),
      _player.stream.log.listen((entry) {
        // Log interno do libmpv (debug): mostra a causa (TLS, DNS,
        // demuxer) que o `error` resume como "Failed to open".
        assert(() {
          debugPrint(
              '[player-diag] mpv/${entry.level}/${entry.prefix}: ${entry.text}');
          return true;
        }());
      }),
      _player.stream.error.listen((message) {
        _errorMessage = message.isEmpty ? null : message;
        // Diagnostico de aparelho (debug): a mensagem nativa nunca vai
        // para a tela nem para o log tecnico (pode conter URL), so para
        // o logcat em build debug.
        if (message.isNotEmpty) {
          assert(() {
            debugPrint('[player-diag] mpv error: $message');
            return true;
          }());
        }
        _emit();
      }),
    ]);
  }

  // Em debug, verbose expõe a causa de "Failed to open" (TLS, DNS,
  // HTTP); em release, error (padrao).
  final Player _player = Player(
    configuration: const PlayerConfiguration(
      logLevel: kDebugMode ? MPVLogLevel.v : MPVLogLevel.error,
    ),
  );
  late final VideoController _videoController;
  final _sessionController = StreamController<PlaybackSession>.broadcast();
  final _subscriptions = <StreamSubscription>[];

  String? _mediaId;
  bool _hasMedia = false;
  bool _playing = false;
  bool _completed = false;
  bool _buffering = false;
  bool _muted = false;
  double _preMuteVolume = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  double _rate = 1.0;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  int _rotation = 0;
  String? _errorMessage;

  PlaybackSession _session = const PlaybackSession();

  @override
  PlaybackSession get session => _session;

  @override
  Stream<PlaybackSession> get sessionStream => _sessionController.stream;

  @override
  Widget buildVideoView() {
    return SizedBox.expand(
      child: Video(
        controller: _videoController,
        // Desliga a barra embutida do media_kit_video (o default e
        // AdaptiveVideoControls): o app desenha os proprios controles e
        // as duas barras apareciam sobrepostas.
        controls: NoVideoControls,
      ),
    );
  }

  @override
  Future<void> open(MediaItem item) async {
    _mediaId = item.id;
    _hasMedia = true;
    _completed = false;
    _rotation = 0;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _tracks = const Tracks();
    _emit(statusOverride: PlaybackStatus.loading);
    final uri = item.sourceType == MediaSourceType.local
        ? Uri.file(item.source).toString()
        : item.source;
    await _player.open(Media(uri));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _hasMedia = false;
    _playing = false;
    _completed = false;
    _buffering = false;
    _mediaId = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _tracks = const Tracks();
    _errorMessage = null;
    await _player.stop();
    _emit();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> seekBy(Duration offset) => seek(session.position + offset);

  @override
  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped > 0) _muted = false;
    await _player.setVolume(clamped * 100);
  }

  @override
  Future<void> setMuted(bool muted) async {
    // O media_kit nao expoe mudo: emula com volume zero e restauracao.
    if (muted == _muted) return;
    _muted = muted;
    if (muted) {
      _preMuteVolume = _volume <= 0 ? 1.0 : _volume;
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_preMuteVolume * 100);
    }
    _emit();
  }

  @override
  Future<void> setSpeed(double value) => _player.setRate(value);

  @override
  Future<void> selectAudio(String trackId) async {
    final match = _findById(_tracks.audio, trackId);
    await _player.setAudioTrack(match ?? AudioTrack(trackId, null, null));
  }

  @override
  Future<void> selectSubtitle(String? trackId) async {
    if (trackId == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final match = _findById(_tracks.subtitle, trackId);
    await _player.setSubtitleTrack(match ?? SubtitleTrack(trackId, null, null));
  }

  @override
  Future<void> selectVideo(String? trackId) async {
    if (trackId == null) {
      await _player.setVideoTrack(VideoTrack.auto());
      return;
    }
    final match = _findById(_tracks.video, trackId);
    await _player.setVideoTrack(match ?? VideoTrack(trackId, null, null));
  }

  static T? _findById<T>(List<T> tracks, String id) {
    for (final track in tracks) {
      if ((track as dynamic).id == id) return track;
    }
    return null;
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) {
    return _player.setPlaylistMode(switch (mode) {
      PlaybackRepeatMode.one => PlaylistMode.single,
      PlaybackRepeatMode.all => PlaylistMode.loop,
      PlaybackRepeatMode.off => PlaylistMode.none,
    });
  }

  @override
  Future<void> rotateClockwise() async {
    _rotation = (_rotation + 1) % 4;
    _emit();
  }

  @override
  Future<void> rotateCounterClockwise() async {
    _rotation = (_rotation + 3) % 4;
    _emit();
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _sessionController.close();
    await _player.dispose();
  }

  void _emit({PlaybackStatus? statusOverride}) {
    // Sentinelas do mpv (auto/no) nao sao faixas reais: fora das listas.
    // Sem arquivo carregado (ex. apos o fim), as listas ficam vazias e a
    // UI mostra "nenhuma disponivel" em vez de lixo.
    bool isReal(String id) => id != 'auto' && id != 'no';
    final audioTracks = _tracks.audio
        .where((t) => isReal(t.id))
        .map((t) =>
            MediaTrack(id: t.id, label: _label(t), language: t.language))
        .toList();
    final subtitleTracks = _tracks.subtitle
        .where((t) => isReal(t.id))
        .map((t) =>
            MediaTrack(id: t.id, label: _label(t), language: t.language))
        .toList();
    final videoTracks = _tracks.video
        .where((t) => isReal(t.id))
        .map((t) =>
            MediaTrack(id: t.id, label: _label(t), language: t.language))
        .toList();
    _session = PlaybackSession(
      mediaId: _mediaId,
      status: statusOverride ?? _deriveStatus(),
      position: _position,
      duration: _duration > Duration.zero ? _duration : null,
      volume: _volume,
      isMuted: _muted,
      speed: _rate,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      videoTracks: videoTracks,
      selectedAudioId: _selectedId(_track.audio.id),
      selectedSubtitleId: _selectedId(_track.subtitle.id),
      selectedVideoId: _selectedId(_track.video.id),
      repeatMode: _repeatMode,
      rotation: _rotation,
      errorMessage: _errorMessage,
    );
    if (!_sessionController.isClosed) _sessionController.add(_session);
  }

  PlaybackStatus _deriveStatus() {
    if (_errorMessage != null) return PlaybackStatus.error;
    if (!_hasMedia) return PlaybackStatus.idle;
    if (_completed) return PlaybackStatus.completed;
    if (_buffering && _playing) return PlaybackStatus.buffering;
    if (_playing) return PlaybackStatus.playing;
    if (_duration <= Duration.zero) return PlaybackStatus.loading;
    return PlaybackStatus.paused;
  }

  /// Rotulo amigavel: titulo, ou idioma, ou "Faixa <id>".
  static String _label(dynamic track) {
    final title = track.title as String?;
    if (title != null && title.isNotEmpty) return title;
    final language = track.language as String?;
    if (language != null && language.isNotEmpty) return language;
    return 'Faixa ${track.id}';
  }

  /// Sentinelas do mpv viram null (trilha desativada).
  static String? _selectedId(String id) =>
      (id == 'no' || id == 'auto') ? null : id;
}
