import 'package:player/models/media_item.dart';

/// Formata [duration] como "12:34" ou "1:12:34". Valores negativos viram zero.
String formatTimestamp(Duration duration) {
  final total = duration.isNegative ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Titulo amigavel a partir de um caminho ou URL: ultimo segmento, sem
/// extensao, com "_" e "-" virando espaco.
String titleFromSource(String source) {
  var name = source.split('/').last.split(r'\').last;
  name = name.split('?').first;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  return name.isEmpty ? 'Vídeo sem título' : name;
}

/// Rotulo de proveniencia para as informacoes do video (spec 26.12):
/// arquivo local, add-on que resolveu (gravado em [MediaItem.metadata]
/// pelo [resolvePlayback]) ou link direto.
String sourceLabelFor(MediaItem item) {
  if (item.sourceType == MediaSourceType.local) return 'Arquivo local';
  final addon = (item.metadata['addonName'] ?? '').trim();
  if (addon.isNotEmpty) return 'Add-on $addon';
  return 'Link';
}

/// Validacao basica de URL na borda (spec 10): aceita http/https nao vazias.
bool isSupportedUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
