import 'package:player/core/utils/media_utils.dart';

/// Atalhos de apresentacao para duracoes.
extension DisplayDuration on Duration {
  /// "12:34" ou "1:12:34".
  String get timestamp => formatTimestamp(this);
}
