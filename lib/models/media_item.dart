import 'package:player/core/constants/app_constants.dart';

/// Item de midia da biblioteca (spec 5.1). Imutavel: alteracoes produzem uma
/// copia via [copyWith]. Serializacao em [toMap]/[fromMap] para o
/// armazenamento local.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.sourceType,
    required this.source,
    this.thumbnailPath,
    this.duration,
    this.lastPosition,
    required this.addedAt,
    this.lastPlayedAt,
    this.isFavorite = false,
    this.audioTrackId,
    this.subtitleTrackId,
    this.metadata = const {},
  });

  final String id;
  final String title;
  final String? subtitle;
  final MediaSourceType sourceType;
  final String source;
  final String? thumbnailPath;
  final Duration? duration;
  final Duration? lastPosition;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final bool isFavorite;
  final String? audioTrackId;
  final String? subtitleTrackId;
  final Map<String, String> metadata;

  /// Percentual assistido entre 0.0 e 1.0, ou null sem dados suficientes.
  double? get progress {
    final total = duration;
    final position = lastPosition;
    if (total == null || total.inMilliseconds <= 0 || position == null) {
      return null;
    }
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Item pode entrar em "Continuar assistindo": tem posicao salva e nao
  /// esta concluido (fracao assistida abaixo de
  /// [AppConstants.completedThreshold]).
  bool get isResumable {
    final total = duration;
    final position = lastPosition;
    if (position == null || position <= Duration.zero) return false;
    if (total == null) return true;
    return !AppConstants.isCompletedPosition(
        position: position, duration: total);
  }

  MediaItem copyWith({
    String? title,
    String? Function()? subtitle,
    String? source,
    String? Function()? thumbnailPath,
    Duration? Function()? duration,
    Duration? Function()? lastPosition,
    DateTime? Function()? lastPlayedAt,
    bool? isFavorite,
    String? Function()? audioTrackId,
    String? Function()? subtitleTrackId,
  }) {
    return MediaItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle != null ? subtitle() : this.subtitle,
      sourceType: sourceType,
      source: source ?? this.source,
      thumbnailPath:
          thumbnailPath != null ? thumbnailPath() : this.thumbnailPath,
      duration: duration != null ? duration() : this.duration,
      lastPosition: lastPosition != null ? lastPosition() : this.lastPosition,
      addedAt: addedAt,
      lastPlayedAt: lastPlayedAt != null ? lastPlayedAt() : this.lastPlayedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      audioTrackId: audioTrackId != null ? audioTrackId() : this.audioTrackId,
      subtitleTrackId:
          subtitleTrackId != null ? subtitleTrackId() : this.subtitleTrackId,
      metadata: metadata,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'sourceType': sourceType.name,
        'source': source,
        'thumbnailPath': thumbnailPath,
        'durationMs': duration?.inMilliseconds,
        'lastPositionMs': lastPosition?.inMilliseconds,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'isFavorite': isFavorite,
        'audioTrackId': audioTrackId,
        'subtitleTrackId': subtitleTrackId,
        'metadata': metadata,
      };

  factory MediaItem.fromMap(Map<String, Object?> map) {
    return MediaItem(
      id: map['id']! as String,
      title: map['title']! as String,
      subtitle: map['subtitle'] as String?,
      sourceType: MediaSourceType.values.byName(map['sourceType']! as String),
      source: map['source']! as String,
      thumbnailPath: map['thumbnailPath'] as String?,
      duration: _durationOrNull(map['durationMs']),
      lastPosition: _durationOrNull(map['lastPositionMs']),
      addedAt: DateTime.parse(map['addedAt']! as String),
      lastPlayedAt: map['lastPlayedAt'] == null
          ? null
          : DateTime.parse(map['lastPlayedAt']! as String),
      isFavorite: (map['isFavorite'] ?? false) as bool,
      audioTrackId: map['audioTrackId'] as String?,
      subtitleTrackId: map['subtitleTrackId'] as String?,
      metadata: (map['metadata'] as Map? ?? {}).cast<String, String>(),
    );
  }

  static Duration? _durationOrNull(Object? ms) =>
      ms == null ? null : Duration(milliseconds: (ms as num).toInt());
}

enum MediaSourceType { local, url }
