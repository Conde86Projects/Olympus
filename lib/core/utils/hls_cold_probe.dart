import 'dart:async';

import 'package:player/core/utils/hls_variants.dart';

/// Desfecho da detecção fria de variantes HLS.
enum HlsColdOutcome {
  /// Rede pronta: variantes na primeira tentativa, sem retry.
  ready,

  /// Rede fria com recuperação: a tentativa posterior aqueceu a lista.
  recovered,

  /// Falha permanente: tentativas esgotadas, segue no master.
  failed,

  /// Sem variantes (playlist simples ou URL fora de HLS): nada a aquecer.
  empty,
}

/// Resultado da detecção fria: variantes reais (vazias quando não há)
/// mais o desfecho e quantas buscas textuais foram feitas.
class HlsColdResult {
  const HlsColdResult({
    required this.variants,
    required this.outcome,
    required this.fetchCount,
  });

  final List<HlsVariant> variants;
  final HlsColdOutcome outcome;
  final int fetchCount;
}

/// Destino do log da sonda fria: só etapa + detalhe numérico.
/// Nunca recebe URL, corpo, token ou mensagem nativa.
typedef HlsColdLog = void Function(String stage, {String? detail});

/// Detecção fria de variantes HLS (investigação separada da retomada
/// aprovada): no boot com rede fria o fetch do master falha e a
/// abertura cai no master pelo fallback; esta sonda faz no máximo UMA
/// tentativa posterior, limitada por timeout, só para aquecer a lista
/// do seletor — nunca troca qualidade, reabre, busca posição ou toca
/// em histórico/ID (isso fica com quem chama, que só atribui a lista).
abstract final class HlsColdProbe {
  /// Espera antes da tentativa posterior (segundo plano, sem travar).
  static const retryDelay = Duration(seconds: 3);

  /// Teto de cada busca textual (master cabe folgado).
  static const fetchTimeout = Duration(seconds: 4);

  /// Sonda completa: tenta, e só em falha de rede (exceção/timeout)
  /// espera [retryDelay] e tenta UMA vez mais. Playlist simples ou
  /// URL fora de HLS é definitiva ([HlsColdOutcome.empty], sem retry).
  /// No máximo duas buscas no total; com [maxAttempts] 1, só uma.
  static Future<HlsColdResult> probe(
    String masterUrl, {
    Future<String> Function(Uri uri)? fetchText,
    int maxAttempts = 2,
    Duration timeout = fetchTimeout,
    Duration retryDelay = retryDelay,
    HlsColdLog? log,
  }) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    final base = Uri.tryParse(masterUrl);
    if (base == null || !base.hasScheme) {
      log?.call('cold-empty', detail: 'attempt=0 count=0');
      return const HlsColdResult(
        variants: [],
        outcome: HlsColdOutcome.empty,
        fetchCount: 0,
      );
    }
    if (!base.path.toLowerCase().endsWith('.m3u8')) {
      log?.call('cold-empty', detail: 'attempt=0 count=0');
      return const HlsColdResult(
        variants: [],
        outcome: HlsColdOutcome.empty,
        fetchCount: 0,
      );
    }
    var fetchCount = 0;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      fetchCount++;
      List<HlsVariant>? variants;
      try {
        final Future<String> Function(Uri uri) text =
            fetchText ?? HlsVariants.fetchMasterText;
        final body = await text(base).timeout(timeout);
        variants = HlsVariants.parseMaster(body, base);
      } catch (_) {
        variants = null;
      }
      if (variants != null) {
        if (variants.isNotEmpty) {
          final recovered = attempt > 1;
          log?.call(
            recovered ? 'cold-recovered' : 'cold-ready',
            detail: 'attempt=$attempt count=${variants.length}',
          );
          return HlsColdResult(
            variants: variants,
            outcome:
                recovered ? HlsColdOutcome.recovered : HlsColdOutcome.ready,
            fetchCount: fetchCount,
          );
        }
        log?.call('cold-empty', detail: 'attempt=$attempt count=0');
        return HlsColdResult(
          variants: const [],
          outcome: HlsColdOutcome.empty,
          fetchCount: fetchCount,
        );
      }
      if (attempt < attempts) {
        log?.call('cold-miss', detail: 'attempt=$attempt');
        await Future.delayed(retryDelay);
      } else {
        log?.call('cold-failed', detail: 'attempt=$attempt');
        return HlsColdResult(
          variants: const [],
          outcome: HlsColdOutcome.failed,
          fetchCount: fetchCount,
        );
      }
    }
    log?.call('cold-failed', detail: 'attempt=$attempts');
    return HlsColdResult(
      variants: const [],
      outcome: HlsColdOutcome.failed,
      fetchCount: fetchCount,
    );
  }
}
