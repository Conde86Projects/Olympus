import 'dart:convert';

import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';

/// Qualidade/rendicao informada pela fonte (5C). Opcional: sem ela,
/// a resolucao usa [AddonCatalogItem.sourceUrl] como padrao.
class SourceQuality {
  const SourceQuality({
    required this.id,
    required this.label,
    required this.sourceUrl,
  });

  final String id;
  final String label;
  final String sourceUrl;

  factory SourceQuality.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final label = json['label'];
    final sourceUrl = json['sourceUrl'];
    if (id is! String ||
        id.isEmpty ||
        label is! String ||
        label.isEmpty ||
        sourceUrl is! String ||
        !isSupportedUrl(sourceUrl)) {
      throw const AddonError.invalidManifest(
        'Qualidade do item de catálogo inválida.',
      );
    }
    return SourceQuality(id: id, label: label, sourceUrl: sourceUrl);
  }
}

/// Item de catalogo oferecido por um add-on. Somente leitura: o servico
/// resolve para [MediaItem] na hora de reproduzir. Nao e persistido.
/// Miniatura e qualidades so existem quando a fonte informa (5C).
class AddonCatalogItem {
  const AddonCatalogItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.sourceUrl,
    this.duration,
    this.thumbnailUrl,
    this.qualities = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String sourceUrl;
  final Duration? duration;
  final String? thumbnailUrl;
  final List<SourceQuality> qualities;

  /// Valida um item vindo de fora (Fase 5: catalogo remoto e dado nao
  /// confiavel). Tipos errados, campos vazios ou URL invalida viram
  /// [AddonError] com o motivo, nunca um item pela metade.
  factory AddonCatalogItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const AddonError.invalidManifest(
        'Item de catálogo sem identificador.',
      );
    }
    final title = json['title'];
    if (title is! String || title.isEmpty) {
      throw const AddonError.invalidManifest(
        'Item de catálogo sem título.',
      );
    }
    final sourceUrl = json['sourceUrl'];
    if (sourceUrl is! String || !isSupportedUrl(sourceUrl)) {
      throw const AddonError.invalidManifest(
        'Item de catálogo sem endereço de mídia válido.',
      );
    }
    final subtitle = json['subtitle'];
    if (subtitle != null && subtitle is! String) {
      throw const AddonError.invalidManifest(
        'Subtítulo do item de catálogo inválido.',
      );
    }
    Duration? duration;
    final rawDuration = json['duration'];
    if (rawDuration != null) {
      final seconds = rawDuration is int
          ? rawDuration
          : (rawDuration is double ? rawDuration.round() : -1);
      if (seconds < 0) {
        throw const AddonError.invalidManifest(
          'Duração do item de catálogo inválida.',
        );
      }
      duration = Duration(seconds: seconds);
    }
    final thumbnailUrl = json['thumbnailUrl'];
    if (thumbnailUrl != null &&
        (thumbnailUrl is! String || !isSupportedUrl(thumbnailUrl))) {
      throw const AddonError.invalidManifest(
        'Miniatura do item de catálogo inválida.',
      );
    }
    final qualities = <SourceQuality>[];
    final rawQualities = json['qualities'];
    if (rawQualities != null) {
      if (rawQualities is! List) {
        throw const AddonError.invalidManifest(
          'Qualidades do item de catálogo inválidas.',
        );
      }
      for (final raw in rawQualities) {
        if (raw is! Map) {
          throw const AddonError.invalidManifest(
            'Qualidade do item de catálogo inválida.',
          );
        }
        qualities.add(
            SourceQuality.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    return AddonCatalogItem(
      id: id,
      title: title,
      subtitle: subtitle as String?,
      sourceUrl: sourceUrl,
      duration: duration,
      thumbnailUrl: thumbnailUrl as String?,
      qualities: List.unmodifiable(qualities),
    );
  }
}

/// Pagina de catalogo (Fase 5): listas remotas sempre paginam, nunca
/// devolvem tudo de uma vez.
class AddonCatalogPage {
  const AddonCatalogPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalItems,
  });

  final List<AddonCatalogItem> items;
  final int page;
  final int pageSize;
  final int totalItems;

  bool get hasMore => page * pageSize < totalItems;
}

/// Fatiamento compartilhado: paginas comecam em 1, tamanho minimo 1.
/// Pagina alem do fim devolve lista vazia (nunca erro).
AddonCatalogPage paginateCatalogItems(
  List<AddonCatalogItem> all, {
  int page = 1,
  int pageSize = 20,
}) {
  final safePage = page < 1 ? 1 : page;
  final safeSize = pageSize < 1 ? 20 : pageSize;
  final start = (safePage - 1) * safeSize;
  final items = start >= all.length
      ? const <AddonCatalogItem>[]
      : all.sublist(start, (start + safeSize).clamp(0, all.length));
  return AddonCatalogPage(
    items: List.unmodifiable(items),
    page: safePage,
    pageSize: safeSize,
    totalItems: all.length,
  );
}

/// Envelope do catalogo remoto: `{"items": [...]}`. Corpo malformado
/// vira [AddonError]; limite de 500 itens por resposta.
List<AddonCatalogItem> parseCatalogItems(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const AddonError.invalidManifest(
      'Catálogo inválido: resposta não é um JSON.',
    );
  }
  if (decoded is! Map || decoded['items'] is! List) {
    throw const AddonError.invalidManifest(
      'Catálogo inválido: esperado {"items": [...]}.',
    );
  }
  final raw = decoded['items'] as List;
  if (raw.length > 500) {
    throw const AddonError.invalidManifest(
      'Catálogo grande demais (limite de 500 itens).',
    );
  }
  // Tolerancia por item (spec 6.1.1): itens invalidos sao pulados,
  // nunca invalidam os validos. Feed sem nenhum item valido e
  // inutil e isola a fonte como malformado.
  final items = <AddonCatalogItem>[];
  for (final entry in raw) {
    try {
      if (entry is! Map) continue;
      items.add(AddonCatalogItem.fromJson(Map<String, Object?>.from(entry)));
    } on AddonError {
      continue;
    }
  }
  if (raw.isNotEmpty && items.isEmpty) {
    throw const AddonError.invalidManifest(
      'Catálogo sem nenhum item válido.',
    );
  }
  return items;
}

/// Serializa rendicoes para o metadata (sempre string): o player
/// decodifica para montar o menu de qualidades da fonte.
String encodeSourceQualities(List<SourceQuality> qualities) =>
    jsonEncode([
      for (final q in qualities)
        {'id': q.id, 'label': q.label, 'sourceUrl': q.sourceUrl},
    ]);

/// Decodifica com tolerancia: corpo estranho vira lista vazia (a
/// midia toca na URL padrao) e entradas invalidas sao puladas.
List<SourceQuality> decodeSourceQualities(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final qualities = <SourceQuality>[];
  for (final entry in decoded) {
    try {
      if (entry is! Map) continue;
      qualities.add(
          SourceQuality.fromJson(Map<String, Object?>.from(entry)));
    } on AddonError {
      continue;
    }
  }
  return qualities;
}
