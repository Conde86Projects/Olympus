import 'package:player/core/constants/app_constants.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/startup_guard.dart';

/// Linhas do diálogo "Informações técnicas" do erro de reprodução.
/// Nunca traz caminho de pastas, endereço completo nem credenciais:
/// arquivo mostra só o nome, link mostra só o servidor, e a mensagem do
/// motor passa pelo mesmo limpador do diagnóstico.
List<MapEntry<String, String>> buildErrorDetails({
  required PlaybackErrorKind? kind,
  required MediaItem item,
  required String? engineMessage,
}) {
  final isLocal = item.sourceType == MediaSourceType.local;
  final source = isLocal ? _fileName(item.source) : _host(item.source);
  final message = engineMessage == null || engineMessage.trim().isEmpty
      ? 'Sem mensagem do motor'
      : StartupGuard.sanitizeErrorText(engineMessage.trim());
  return [
    MapEntry('Tipo do erro',
        playbackErrorKindLabel(kind ?? PlaybackErrorKind.unknown)),
    MapEntry('Tipo da fonte', isLocal ? 'Arquivo' : 'Link'),
    MapEntry(isLocal ? 'Arquivo' : 'Servidor', source),
    MapEntry('Mensagem do motor', message),
    const MapEntry('Versão do app', AppConstants.appVersion),
  ];
}

String _fileName(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  return name.isEmpty ? 'desconhecido' : name;
}

String _host(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.isEmpty ? 'desconhecido' : host;
}
