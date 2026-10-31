import 'dart:async';

import 'package:player/core/utils/hls_cold_probe.dart';
import 'package:player/core/utils/hls_variants.dart';

/// Aquece a lista de variantes depois de uma abertura com rede fria:
/// tentativas espacadas e limitadas ([HlsColdProbe.warmDelays]), em segundo
/// plano. So entrega as variantes; quem chama decide o que fazer com elas e
/// nada aqui abre video, busca posicao ou toca no historico.
class HlsColdWarmer {
  HlsColdWarmer({
    required this.onVariants,
    required this.stillNeeded,
    this.log,
    this.fetchText,
  });

  final void Function(List<HlsVariant> variants) onVariants;

  /// Falso quando outro caminho ja obteve as variantes: para de tentar.
  final bool Function() stillNeeded;

  final HlsColdLog? log;
  final Future<String> Function(Uri uri)? fetchText;

  Timer? _timer;
  int _run = 0;

  /// Comeca do zero para [source], abandonando o que estava em andamento.
  void start(String source) {
    cancel();
    _schedule(source, 0, _run);
  }

  /// Depois disso nenhum resultado e entregue, nem de busca em andamento.
  void cancel() {
    _run++;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(String source, int attempt, int run) {
    if (attempt >= HlsColdProbe.warmDelays.length) return;
    _timer = Timer(HlsColdProbe.warmDelays[attempt], () async {
      _timer = null;
      final result = await HlsColdProbe.probe(
        source,
        fetchText: fetchText,
        maxAttempts: 1,
        log: log,
      );
      if (run != _run || !stillNeeded()) return;
      if (result.variants.isNotEmpty) {
        onVariants(result.variants);
      } else if (result.outcome == HlsColdOutcome.failed) {
        _schedule(source, attempt + 1, run);
      }
    });
  }
}
