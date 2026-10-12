import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';

/// Contrato de reproducao (spec 4.1). A UI depende apenas desta interface;
/// adaptadores por plataforma entram nas Fases 2+ sem refazer as telas.
abstract class MediaPlayerService {
  /// Sessao atual (leitura sincrona para montar a UI inicial).
  PlaybackSession get session;

  /// Emite a sessao a cada mudanca de estado, posicao ou trilha.
  Stream<PlaybackSession> get sessionStream;

  /// Superficie de video da implementacao. Mantem a tela desacoplada da
  /// biblioteca de reproducao: a UI nunca importa o video diretamente.
  Widget buildVideoView();

  /// Abre uma midia. Nao inicia a reproducao sozinho (spec 7: sem autoplay
  /// sem preferencia explicita).
  Future<void> open(MediaItem item);

  Future<void> play();
  Future<void> pause();

  /// Interrompe e libera a sessao atual (volta a ociosidade). Usado
  /// pelo cancelar durante o carregamento e antes de trocar de midia.
  Future<void> stop();

  /// Posicao absoluta. Valores fora do intervalo sao limitados.
  Future<void> seek(Duration position);

  /// Avanca/retrocede relativo, ex. +/- 10 segundos.
  Future<void> seekBy(Duration offset) => seek(session.position + offset);

  /// Volume entre 0.0 e 1.0.
  Future<void> setVolume(double value);

  Future<void> setMuted(bool muted);

  /// Velocidades suportadas pelo menu: 0.5, 1.0, 1.25, 1.5, 2.0 (spec 13).
  Future<void> setSpeed(double value);

  /// `trackId` null desativa a legenda.
  Future<void> selectAudio(String trackId);
  Future<void> selectSubtitle(String? trackId);

  /// Qualidade de vídeo (spec 13): `trackId` null volta ao automático.
  /// A UI só oferece quando a fonte informa múltiplas faixas.
  Future<void> selectVideo(String? trackId);

  Future<void> setRepeatMode(PlaybackRepeatMode mode);

  /// Gira o video em quartos de volta (linha "Girar" do painel).
  /// Normalizado em 0-3 na sessao; so vale para a sessao atual.
  Future<void> rotateClockwise();
  Future<void> rotateCounterClockwise();

  /// Libera recursos do player ao fechar a tela (checklist, spec 23).
  Future<void> dispose();
}

/// Implementacao neutra para o prototipo navegavel (Fase 1): mantem estado
/// em memoria e simula play/pause/seek sem decodificar midia.
class NoOpMediaPlayerService implements MediaPlayerService {
  const NoOpMediaPlayerService();

  static var _session = const PlaybackSession();
  static final _controller = StreamController<PlaybackSession>.broadcast();

  @override
  PlaybackSession get session => _session;

  @override
  Stream<PlaybackSession> get sessionStream => _controller.stream;

  void _emit(PlaybackSession next) {
    _session = next;
    _controller.add(next);
  }

  @override
  Widget buildVideoView() {
    return const ColoredBox(color: Color(0xFF000000));
  }

  @override
  Future<void> open(MediaItem item) async {
    _emit(_session.copyWith(
      mediaId: () => item.id,
      status: PlaybackStatus.ready,
      position: Duration.zero,
      duration: () => item.duration,
      rotation: 0,
    ));
  }

  @override
  Future<void> play() async => _emit(session.copyWith(
        status: session.mediaId == null
            ? PlaybackStatus.idle
            : PlaybackStatus.playing,
      ));

  @override
  Future<void> pause() async => _emit(session.copyWith(
        status: session.status == PlaybackStatus.playing
            ? PlaybackStatus.paused
            : session.status,
      ));

  @override
  Future<void> stop() async => _emit(session.copyWith(
        status: PlaybackStatus.idle,
        position: Duration.zero,
        mediaId: () => null,
        duration: () => null,
        errorMessage: () => null,
        errorKind: () => null,
      ));

  @override
  Future<void> seek(Duration position) async {
    final limit = session.duration ?? const Duration(hours: 2);
    final clamped = position.isNegative
        ? Duration.zero
        : (position > limit ? limit : position);
    _emit(session.copyWith(position: clamped));
  }

  @override
  Future<void> seekBy(Duration offset) => seek(session.position + offset);

  @override
  Future<void> setVolume(double value) async =>
      _emit(session.copyWith(volume: value.clamp(0.0, 1.0)));

  @override
  Future<void> setMuted(bool muted) async =>
      _emit(session.copyWith(isMuted: muted));

  @override
  Future<void> setSpeed(double value) async =>
      _emit(session.copyWith(speed: value));

  @override
  Future<void> selectAudio(String trackId) async =>
      _emit(session.copyWith(selectedAudioId: () => trackId));

  @override
  Future<void> selectSubtitle(String? trackId) async =>
      _emit(session.copyWith(selectedSubtitleId: () => trackId));

  @override
  Future<void> selectVideo(String? trackId) async =>
      _emit(session.copyWith(selectedVideoId: () => trackId));

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async =>
      _emit(session.copyWith(repeatMode: mode));

  @override
  Future<void> rotateClockwise() async =>
      _emit(session.copyWith(rotation: (session.rotation + 1) % 4));

  @override
  Future<void> rotateCounterClockwise() async =>
      _emit(session.copyWith(rotation: (session.rotation + 3) % 4));

  @override
  Future<void> dispose() async {}

  /// Forca um estado (ex. `completed` para as acoes finais). Existe para
  /// testes de UI; nao usar em producao.
  void simulateStatus(PlaybackStatus status) =>
      _emit(session.copyWith(status: status));

  /// Forca um erro classificado, como o supervisor emitiria. Existe
  /// para testes de UI; nao usar em producao.
  void simulateError(PlaybackErrorKind kind, [String? message]) =>
      _emit(session.copyWith(
        status: PlaybackStatus.error,
        errorKind: () => kind,
        errorMessage: () => message,
      ));
}
