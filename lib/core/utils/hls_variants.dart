import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Variante de um master HLS (`EXT-X-STREAM-INF` + URI).
class HlsVariant {
  const HlsVariant({
    required this.uri,
    this.bandwidth,
    this.width,
    this.height,
  });

  /// URI absoluta da variante (resolvida contra o master).
  final Uri uri;

  /// `BANDWIDTH` (bits/s), quando informado.
  final int? bandwidth;

  /// `RESOLUTION` WxH, quando informado.
  final int? width;
  final int? height;
}

/// Teto de variante HLS por classe de TV (SoC fraco): o mpv escolhe
/// sozinho a variante maxima do master e numa TV fraca o render
/// pesado (copia por CPU + upload + shaders) anda a 0,14x. Aqui o
/// app resolve antes de abrir: master -> melhor variante dentro do
/// teto. Playlist simples ou falha de rede: cai na URL original
/// (comportamento atual).
/// Opcao do seletor manual de qualidade HLS. [id] e o que a UI
/// guarda/dispara: [HlsVariants.autoQualityId], [HlsVariants.originalQualityId]
/// ou a URI da variante. [uri] e o alvo concreto (null na Automatica,
/// resolvida na hora conforme o teto da classe).
class HlsQualityOption {
  const HlsQualityOption({required this.id, required this.label, this.uri});

  final String id;
  final String label;
  final Uri? uri;
}

/// Perfil automatico por plataforma/Leanback/viewport. O Leanback
/// chega dobrado em `isTv` (TvInfoService na abertura do app ou
/// interruptor manual); [platform] fica registrado para diagnostico
/// e nunca, sozinho, aplica teto ao desktop.
enum HlsAutoProfile { weakTv, tv, tvBig, desktop }

/// Decisao do perfil automatico: se ha teto e quais os limites.
/// Fora do teto os limites sao os da classe fraca, sem uso.
class HlsAutoDecision {
  const HlsAutoDecision({
    required this.profile,
    required this.capped,
    this.maxHeight = HlsVariants.cappedHeight,
    this.maxBandwidth = HlsVariants.cappedBandwidth,
    this.platform,
  });

  final HlsAutoProfile profile;
  final bool capped;
  final int maxHeight;
  final int maxBandwidth;
  final String? platform;
}

abstract final class HlsVariants {
  /// Id da opcao Automatica (padrao): respeita o teto da classe.
  static const autoQualityId = 'auto';

  /// Limiar da capacidade observada: abaixo dele, um degrau a menos.
  static const observedRatioThreshold = 0.9;

  /// Relogio injetavel do observador de capacidade; producao usa
  /// o relogio do sistema quando null (testes substituem).
  static DateTime Function()? debugNowOverride;

  /// Perfil automatico: TV (Leanback/manual) abaixo de 1280 tetada
  /// com os limites atuais que estabilizaram a TCL; TV grande e
  /// qualquer desktop sem teto. TV sem viewport detectado cai no
  /// teto fraco (fallback seguro); desktop nunca e tetado pelo
  /// tamanho da janela.
  static HlsAutoDecision autoDecision({
    required bool isTv,
    required double? logicalWidth,
    String? platform,
  }) {
    if (!isTv) {
      return HlsAutoDecision(
          profile: HlsAutoProfile.desktop,
          capped: false,
          platform: platform);
    }
    if (logicalWidth == null) {
      return HlsAutoDecision(
          profile: HlsAutoProfile.weakTv,
          capped: true,
          platform: platform);
    }
    if (logicalWidth >= 1280) {
      return HlsAutoDecision(
          profile: HlsAutoProfile.tvBig,
          capped: false,
          platform: platform);
    }
    return HlsAutoDecision(
      profile: logicalWidth < 800
          ? HlsAutoProfile.weakTv
          : HlsAutoProfile.tv,
      capped: true,
      platform: platform,
    );
  }

  /// Tolerancia da retomada HLS: desvio ate aqui e "perto o
  /// bastante" (mesma margem que o fluxo atual ja usava).
  static const resumeTolerance = Duration(seconds: 4);

  /// Prontidão da retomada: intervalo entre amostras de posição e
  /// número máximo de amostras (~8 s). Poll por iteração, não por
  /// relógio, para ser determinístico em teste.
  static const hlsReadyPoll = Duration(milliseconds: 250);
  static const hlsReadyMaxSamples = 32;

  /// Verificação da posição após o seek (estabilização).
  static const hlsVerifyDelay = Duration(seconds: 2);

  /// Validação do pouso após a correção única.
  static const hlsCorrectionSettle = Duration(milliseconds: 1500);

  /// A posicao real exige a correcao unica da retomada?
  static bool resumeNeedsCorrection(
    Duration actual,
    Duration target, {
    Duration tolerance = resumeTolerance,
  }) =>
      (actual - target).abs() > tolerance;

  /// Razao posicao/relógio da capacidade observada. Janela nula ou
  /// negativa: sem medicao (null), nunca um chute.
  static double? playbackRatio(
      Duration startPosition, Duration endPosition, Duration wall) {
    if (wall <= Duration.zero) return null;
    final delta = endPosition - startPosition;
    return delta.inMilliseconds / wall.inMilliseconds;
  }

  /// Variantes ordenadas da maior para a menor, sem URI duplicada.
  static List<HlsVariant> sortedVariants(List<HlsVariant> variants) {
    final sorted = [...variants]..sort((a, b) {
        final byHeight = (b.height ?? -1).compareTo(a.height ?? -1);
        if (byHeight != 0) return byHeight;
        return (b.bandwidth ?? -1).compareTo(a.bandwidth ?? -1);
      });
    final seen = <String>{};
    return [
      for (final v in sorted)
        if (seen.add(v.uri.toString())) v,
    ];
  }

  /// Proxima variante mais leve quando a capacidade observada fica
  /// abaixo do limiar. Saudavel, sem medicao, sem variantes ou ja
  /// na mais leve: null (mantem o que esta tocando). Corrente fora
  /// da lista e o master (mpv na maxima): desce da maior.
  static String? downgradeUrl({
    required String masterUrl,
    required List<HlsVariant> variants,
    required String currentUrl,
    required double? ratio,
    double threshold = observedRatioThreshold,
  }) {
    if (ratio == null || ratio >= threshold) return null;
    final sorted = sortedVariants(variants);
    if (sorted.isEmpty) return null;
    final index =
        sorted.indexWhere((v) => v.uri.toString() == currentUrl);
    if (index >= 0) {
      return index + 1 < sorted.length
          ? sorted[index + 1].uri.toString()
          : null;
    }
    // Master (ou URL fora da lista): a efetiva presumida e a maior.
    return sorted.length >= 2 ? sorted[1].uri.toString() : null;
  }

  /// Id da opcao Original: o master intacto (mpv escolhe). So e
  /// oferecida quando difere da Automatica (classe com teto).
  static const originalQualityId = 'original';
  /// Tetos da classe fraca, medidos na TCL 50" (Mali-470, 4x1,1 GHz):
  /// 1080p60 (124 Mpx/s) anda a 0,14x, 720p60 (55 Mpx/s) a 0,33x e
  /// 480p60 (24 Mpx/s) a 0,6-0,8x; o teto sustentado fica abaixo de
  /// ~15 Mpx/s. 500 kbps pega a 380p30 (4,4 Mpx/s) no master de
  /// referencia. Banda e obrigatoria no master; resolucao nem sempre
  /// vem (sem ela, so a banda decide).
  static const cappedHeight = 720;
  static const cappedBandwidth = 500000;

  /// Busca textual para testes (null = rede de verdade).
  @visibleForTesting
  static Future<String> Function(Uri uri)? debugFetchOverride;

  /// GET textual do master honrando a substituição de teste quando
  /// houver (a sonda fria usa este ponto único, sem tocar o membro
  /// de teste fora daqui).
  static Future<String> fetchMasterText(Uri uri) {
    final fetch = debugFetchOverride ?? fetchText;
    return fetch(uri);
  }

  /// Resolve a URL a abrir: variante tetada ou a original.
  static Future<String> resolve(
    String url, {
    int maxHeight = cappedHeight,
    int maxBandwidth = cappedBandwidth,
    Future<String> Function(Uri uri)? fetchOverride,
  }) async {
    final base = Uri.tryParse(url);
    if (base == null || !base.hasScheme) return url;
    // So tenta em playlist: abrir um .mp4 como texto baixaria o
    // arquivo inteiro. Master com nome exotico segue sem teto.
    if (!base.path.toLowerCase().endsWith('.m3u8')) return url;
    try {
      final fetch = fetchOverride ?? debugFetchOverride ?? fetchText;
      final body =
          await fetch(base).timeout(const Duration(seconds: 4));
      final pick = pickCapped(
        parseMaster(body, base),
        maxHeight: maxHeight,
        maxBandwidth: maxBandwidth,
      );
      return pick?.uri.toString() ?? url;
    } catch (_) {
      return url;
    }
  }

  /// URL da Automatica: com teto, a melhor variante dentro dele;
  /// sem teto, o master. Teto e constantes atuais, sem mudanca.
  static String automaticUrl(
    String masterUrl,
    List<HlsVariant> variants, {
    required bool capped,
    int maxHeight = cappedHeight,
    int maxBandwidth = cappedBandwidth,
  }) {
    if (!capped) return masterUrl;
    final pick = pickCapped(variants,
        maxHeight: maxHeight, maxBandwidth: maxBandwidth);
    return pick?.uri.toString() ?? masterUrl;
  }

  /// Busca e parseia as variantes reais do master. Qualquer falha,
  /// playlist simples ou URL nao-m3u8: lista vazia (nada inventado).
  static Future<List<HlsVariant>> fetchVariants(
    String url, {
    Future<String> Function(Uri uri)? fetchOverride,
  }) async {
    final base = Uri.tryParse(url);
    if (base == null || !base.hasScheme) return const [];
    if (!base.path.toLowerCase().endsWith('.m3u8')) return const [];
    try {
      final fetch = fetchOverride ?? debugFetchOverride ?? fetchText;
      final body = await fetch(base).timeout(const Duration(seconds: 4));
      return parseMaster(body, base);
    } catch (_) {
      return const [];
    }
  }

  /// Rotulo curto da variante: altura quando ha, senao a banda.
  static String variantLabel(HlsVariant variant) {
    if (variant.height != null) return '${variant.height}p';
    if (variant.bandwidth != null) {
      return '${(variant.bandwidth! / 1000).round()} kbps';
    }
    return 'Variante';
  }

  /// Opcoes do seletor: Automatica primeiro, Original (quando
  /// [includeOriginal]) e as variantes da maior para a menor,
  /// sem URIs duplicadas. Rotulos repetidos ganham a banda.
  static List<HlsQualityOption> qualityOptions(
    List<HlsVariant> variants, {
    required bool includeOriginal,
  }) {
    final sorted = [...variants]..sort((a, b) {
        final byHeight = (b.height ?? -1).compareTo(a.height ?? -1);
        if (byHeight != 0) return byHeight;
        return (b.bandwidth ?? -1).compareTo(a.bandwidth ?? -1);
      });
    final seen = <String>{};
    final unique = <HlsVariant>[];
    for (final v in sorted) {
      if (seen.add(v.uri.toString())) unique.add(v);
    }
    final labelCount = <String, int>{};
    for (final v in unique) {
      final label = variantLabel(v);
      labelCount[label] = (labelCount[label] ?? 0) + 1;
    }
    return [
      const HlsQualityOption(id: autoQualityId, label: 'Automática'),
      if (includeOriginal && unique.isNotEmpty)
        const HlsQualityOption(
            id: originalQualityId, label: 'Original'),
      for (final v in unique)
        HlsQualityOption(
          id: v.uri.toString(),
          label: (labelCount[variantLabel(v)] ?? 0) > 1 &&
                  v.bandwidth != null
              ? '${variantLabel(v)} · ${(v.bandwidth! / 1000).round()} kbps'
              : variantLabel(v),
          uri: v.uri,
        ),
    ];
  }

  /// Melhor variante dentro dos tetos (maior `BANDWIDTH` que passa
  /// nos dois; altura ausente nao desclassifica). Nenhuma passando:
  /// a mais leve (sempre melhor que o master, que o mpv abriria no
  /// maximo). Lista vazia: nulo (abre a original).
  static HlsVariant? pickCapped(
    List<HlsVariant> variants, {
    required int maxHeight,
    required int maxBandwidth,
  }) {
    if (variants.isEmpty) return null;
    HlsVariant? best;
    for (final v in variants) {
      if (v.height != null && v.height! > maxHeight) continue;
      if (v.bandwidth != null && v.bandwidth! > maxBandwidth) continue;
      if (best == null || (v.bandwidth ?? -1) > (best.bandwidth ?? -1)) {
        best = v;
      }
    }
    if (best != null) return best;
    HlsVariant lightest = variants.first;
    for (final v in variants) {
      if ((v.bandwidth ?? -1) < (lightest.bandwidth ?? -1)) {
        lightest = v;
      }
    }
    return lightest;
  }

  /// Parseia master (`[]` se nao for master ou vier quebrado).
  static List<HlsVariant> parseMaster(String body, Uri base) {
    final lines = body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first != '#EXTM3U') return const [];
    final variants = <HlsVariant>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attrs = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
      String? uriLine;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].startsWith('#')) continue;
        uriLine = lines[j];
        break;
      }
      if (uriLine == null) continue;
      final resolution = attrs['RESOLUTION'];
      int? width;
      int? height;
      if (resolution != null) {
        final parts = resolution.toLowerCase().split('x');
        if (parts.length == 2) {
          width = int.tryParse(parts[0]);
          height = int.tryParse(parts[1]);
        }
      }
      variants.add(HlsVariant(
        uri: base.resolve(uriLine),
        bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? ''),
        width: width,
        height: height,
      ));
    }
    return variants;
  }

  /// Atributos `CHAVE=valor` (valor pode ter virgula entre aspas).
  static Map<String, String> _attributes(String raw) {
    final attrs = <String, String>{};
    final current = StringBuffer();
    String? key;
    var inQuotes = false;
    void flush() {
      if (key == null) return;
      var value = current.toString();
      if (value.length >= 2 &&
          value.startsWith('"') &&
          value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      attrs[key!] = value;
      current.clear();
      key = null;
    }

    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        current.write(char);
      } else if (char == '=' && key == null && !inQuotes) {
        key = current.toString();
        current.clear();
      } else if (char == ',' && !inQuotes) {
        flush();
      } else {
        current.write(char);
      }
    }
    flush();
    return attrs;
  }

  /// GET textual com teto de 64 KB (master cabe folgado).
  static Future<String> fetchText(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }
}
