/// Registro do historico (spec 15.3). Imutavel.
class HistoryEntry {
  const HistoryEntry({
    required this.mediaId,
    required this.accessedAt,
    this.position,
    this.percentWatched,
    this.completed = false,
  });

  final String mediaId;
  final DateTime accessedAt;
  final Duration? position;
  final double? percentWatched;
  final bool completed;

  HistoryEntry copyWith({
    DateTime? accessedAt,
    Duration? Function()? position,
    double? Function()? percentWatched,
    bool? completed,
  }) {
    return HistoryEntry(
      mediaId: mediaId,
      accessedAt: accessedAt ?? this.accessedAt,
      position: position != null ? position() : this.position,
      percentWatched:
          percentWatched != null ? percentWatched() : this.percentWatched,
      completed: completed ?? this.completed,
    );
  }

  Map<String, Object?> toMap() => {
        'mediaId': mediaId,
        'accessedAt': accessedAt.toIso8601String(),
        'positionMs': position?.inMilliseconds,
        'percentWatched': percentWatched,
        'completed': completed,
      };

  factory HistoryEntry.fromMap(Map<String, Object?> map) {
    final ms = map['positionMs'];
    return HistoryEntry(
      mediaId: map['mediaId']! as String,
      accessedAt: DateTime.parse(map['accessedAt']! as String),
      position: ms == null ? null : Duration(milliseconds: (ms as num).toInt()),
      percentWatched: (map['percentWatched'] as num?)?.toDouble(),
      completed: (map['completed'] ?? false) as bool,
    );
  }
}
