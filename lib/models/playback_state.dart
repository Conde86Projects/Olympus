/// Faixa de audio ou legenda disponivel na midia atual.
class MediaTrack {
  const MediaTrack({required this.id, required this.label, this.language});

  final String id;
  final String label;

  /// Codigo de idioma da faixa (ex. "por", "eng"), quando o player informa.
  /// Usado para casar o idioma preferido das preferencias (spec 16).
  final String? language;
}

/// Repeticao (menu do player, spec 13). Nome qualificado porque o Flutter
/// ja exporta um `RepeatMode` proprio pelo material.
enum PlaybackRepeatMode { off, one, all }

/// Tipo do erro de reproducao (spec 17, 26). Decide a mensagem
/// exibida: rede, fonte, decodificador, tempo esgotado ou desconhecido.
/// Erros nativos chegam como texto e passam por [classifyPlaybackError].
enum PlaybackErrorKind { network, source, decoder, timeout, unknown }

/// Classifica a mensagem nativa (mpv) por palavras-chave. Heuristica
/// assumida: as strings do motor nao sao contrato estavel, entao o
/// padrao e [PlaybackErrorKind.unknown] e a ordem importa (404 e fonte,
/// nao rede; timeout antes de rede generica).
PlaybackErrorKind classifyPlaybackError(String? message) {
  if (message == null || message.isEmpty) return PlaybackErrorKind.unknown;
  final text = message.toLowerCase();
  if (text.contains('timed out') || text.contains('timeout')) {
    return PlaybackErrorKind.timeout;
  }
  if (text.contains('404') ||
      // 403 e resposta da fonte (link revogado/bloqueado), nao falta
      // de rede: vinha caindo em "http error" -> rede (TCL, 11/10/2026).
      text.contains('403') ||
      text.contains('forbidden') ||
      text.contains('not found') ||
      text.contains('no such file') ||
      text.contains('unable to open') ||
      // F9 (Fase 4b): arquivo local sem permissao de leitura. Vem
      // antes da rede porque o mpv diz "Failed to open ...", que
      // sozinho cairia em rede (diagnostico errado no aparelho).
      text.contains('permission denied') ||
      text.contains('eperm') ||
      text.contains('access is denied')) {
    return PlaybackErrorKind.source;
  }
  if (text.contains('codec') ||
      text.contains('decoder') ||
      text.contains('decod') ||
      text.contains('unsupported') ||
      text.contains('format not supported')) {
    return PlaybackErrorKind.decoder;
  }
  if (text.contains('connection') ||
      text.contains('network') ||
      text.contains('resolve') ||
      text.contains('dns') ||
      text.contains('socket') ||
      text.contains('econn') ||
      text.contains('eai_') ||
      text.contains('http error') ||
      text.contains('failed to load') ||
      text.contains('failed to open')) {
    return PlaybackErrorKind.network;
  }
  return PlaybackErrorKind.unknown;
}

/// Rotulo curto e neutro do tipo (diagnostico e exportacao): sem
/// caminhos, URLs ou detalhes da mensagem original.
String playbackErrorKindLabel(PlaybackErrorKind kind) => switch (kind) {
      PlaybackErrorKind.network => 'rede',
      PlaybackErrorKind.source => 'fonte',
      PlaybackErrorKind.decoder => 'decodificador',
      PlaybackErrorKind.timeout => 'tempo esgotado',
      PlaybackErrorKind.unknown => 'desconhecido',
    };

/// Estado de reproducao (spec 5.2).
enum PlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
}

/// Sessao de reproducao: tudo que a UI precisa observar. Imutavel.
class PlaybackSession {
  const PlaybackSession({
    this.mediaId,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1.0,
    this.isMuted = false,
    this.speed = 1.0,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.videoTracks = const [],
    this.selectedAudioId,
    this.selectedSubtitleId,
    this.selectedVideoId,
    this.repeatMode = PlaybackRepeatMode.off,
    this.rotation = 0,
    this.isFullscreen = false,
    this.isCompact = false,
    this.errorMessage,
    this.errorKind,
  });

  final String? mediaId;
  final PlaybackStatus status;
  final Duration position;
  final Duration? duration;
  final double volume;
  final bool isMuted;
  final double speed;
  final List<MediaTrack> audioTracks;
  final List<MediaTrack> subtitleTracks;

  /// Faixas de vídeo (qualidades) informadas pela fonte. A seção
  /// "Qualidade" só aparece com mais de uma (spec 13).
  final List<MediaTrack> videoTracks;
  final String? selectedAudioId;
  final String? selectedSubtitleId;

  /// Faixa de vídeo ativa; null = automática.
  final String? selectedVideoId;
  final PlaybackRepeatMode repeatMode;

  /// Quartos de volta no sentido horario (0-3). So sessao: nao persiste.
  final int rotation;
  final bool isFullscreen;
  final bool isCompact;
  final String? errorMessage;

  /// Tipo classificado do erro (decide a mensagem da UI). A mensagem
  /// nativa vai para o log tecnico, nunca para a tela (pode conter
  /// caminhos e URLs).
  final PlaybackErrorKind? errorKind;

  PlaybackSession copyWith({
    String? Function()? mediaId,
    PlaybackStatus? status,
    Duration? position,
    Duration? Function()? duration,
    double? volume,
    bool? isMuted,
    double? speed,
    List<MediaTrack>? audioTracks,
    List<MediaTrack>? subtitleTracks,
    List<MediaTrack>? videoTracks,
    String? Function()? selectedAudioId,
    String? Function()? selectedSubtitleId,
    String? Function()? selectedVideoId,
    PlaybackRepeatMode? repeatMode,
    int? rotation,
    bool? isFullscreen,
    bool? isCompact,
    String? Function()? errorMessage,
    PlaybackErrorKind? Function()? errorKind,
  }) {
    return PlaybackSession(
      mediaId: mediaId != null ? mediaId() : this.mediaId,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration != null ? duration() : this.duration,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      speed: speed ?? this.speed,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      videoTracks: videoTracks ?? this.videoTracks,
      selectedAudioId:
          selectedAudioId != null ? selectedAudioId() : this.selectedAudioId,
      selectedSubtitleId: selectedSubtitleId != null
          ? selectedSubtitleId()
          : this.selectedSubtitleId,
      selectedVideoId: selectedVideoId != null
          ? selectedVideoId()
          : this.selectedVideoId,
      repeatMode: repeatMode ?? this.repeatMode,
      rotation: rotation ?? this.rotation,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      isCompact: isCompact ?? this.isCompact,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      errorKind: errorKind != null ? errorKind() : this.errorKind,
    );
  }
}
