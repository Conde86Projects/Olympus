import 'dart:convert';

import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/sources/source_adapter.dart';
import 'package:player/services/sources/source_credentials.dart';

/// Fonte demo realista para testes (5C): formato PROPRIO (prova que o
/// adaptador traduz), paginacao e busca no servidor, miniatura e
/// qualidades opcionais. Host `.invalid` (RFC 2606): nunca resolve de
/// verdade; os testes injetam o corpo via [AddonFetcher] fake. Sem
/// autenticacao: [headersFor] documenta o gancho vazio.
class DemoSourceAdapter extends SourceAdapter {
  const DemoSourceAdapter();

  @override
  String get id => 'demo.source';

  @override
  bool canHandle(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'demo.invalid' || host.endsWith('.demo.invalid');
  }

  @override
  Future<Map<String, String>> headersFor(
    Uri uri,
    SourceCredentialStore credentials,
  ) async {
    return const {};
  }

  /// Envelope demo:
  /// `{"results": [{"video_id","name","file","poster"?,"length"?,
  /// "renditions"?:[{"label","file"}]}], "page"?:1, "total_pages"?:1}`.
  /// Entradas invalidas sao puladas; envelope fora do formato lanca.
  @override
  SourceCatalogPage parseCatalog(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const AddonError.invalidManifest(
        'Catálogo demo inválido: resposta não é um JSON.',
      );
    }
    if (decoded is! Map || decoded['results'] is! List) {
      throw const AddonError.invalidManifest(
        'Catálogo demo inválido: esperado {"results": [...]}.',
      );
    }
    final raw = decoded['results'] as List;
    if (raw.length > 500) {
      throw const AddonError.invalidManifest(
        'Catálogo grande demais (limite de 500 itens).',
      );
    }
    final items = <AddonCatalogItem>[];
    for (final entry in raw) {
      try {
        if (entry is! Map) continue;
        items.add(_itemFrom(Map<String, Object?>.from(entry)));
      } on AddonError {
        continue;
      }
    }
    if (raw.isNotEmpty && items.isEmpty) {
      throw const AddonError.invalidManifest(
        'Catálogo sem nenhum item válido.',
      );
    }
    final page = _asInt(decoded['page'], 1);
    final totalPages = _asInt(decoded['total_pages'], 1);
    return SourceCatalogPage(items: items, hasMore: page < totalPages);
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int && value > 0) return value;
    return fallback;
  }

  AddonCatalogItem _itemFrom(Map<String, Object?> json) {
    final id = json['video_id'];
    final name = json['name'];
    final file = json['file'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        file is! String ||
        !isSupportedUrl(file)) {
      throw const AddonError.invalidManifest(
        'Item do catálogo demo inválido.',
      );
    }
    final poster = json['poster'];
    if (poster != null &&
        (poster is! String || !isSupportedUrl(poster))) {
      throw const AddonError.invalidManifest(
        'Miniatura do item demo inválida.',
      );
    }
    Duration? duration;
    final length = json['length'];
    if (length != null) {
      final seconds =
          length is int ? length : (length is double ? length.round() : -1);
      if (seconds < 0) {
        throw const AddonError.invalidManifest(
          'Duração do item demo inválida.',
        );
      }
      duration = Duration(seconds: seconds);
    }
    final qualities = <SourceQuality>[];
    final renditions = json['renditions'];
    if (renditions != null) {
      if (renditions is! List) {
        throw const AddonError.invalidManifest(
          'Qualidades do item demo inválidas.',
        );
      }
      for (final rendition in renditions) {
        if (rendition is! Map) {
          throw const AddonError.invalidManifest(
            'Qualidade do item demo inválida.',
          );
        }
        final map = Map<String, Object?>.from(rendition);
        final label = map['label'];
        final renditionFile = map['file'];
        if (label is! String ||
            label.isEmpty ||
            renditionFile is! String ||
            !isSupportedUrl(renditionFile)) {
          throw const AddonError.invalidManifest(
            'Qualidade do item demo inválida.',
          );
        }
        qualities.add(SourceQuality(
          id: label,
          label: label,
          sourceUrl: renditionFile,
        ));
      }
    }
    return AddonCatalogItem(
      id: id,
      title: name,
      sourceUrl: file,
      duration: duration,
      thumbnailUrl: poster as String?,
      qualities: List.unmodifiable(qualities),
    );
  }

  @override
  AddonManifest manifestFor(String url, int itemCount) {
    return AddonManifest(
      id: 'demo.source',
      name: 'Fonte Demo (teste)',
      version: '1.0.0',
      author: 'Equipe Player',
      description: 'Fonte demo com $itemCount '
          '${itemCount == 1 ? 'item' : 'itens'} (adaptador de teste).',
      icon: 'rss_feed',
      homepage: 'https://demo.invalid',
      repository: url,
      permissions: const ['catalog.read', 'playback.open'],
      supportedPlatforms: const ['windows', 'linux', 'macos', 'android'],
      contentTypes: const ['video'],
      catalogUrl: url,
      legalNotice: 'Fonte de demonstração para testes. Sem conteúdo real.',
    );
  }

  @override
  Uri? pageUrl(Uri base, int page) {
    if (page < 1) return null;
    final params = Map<String, String>.from(base.queryParameters);
    params['page'] = '$page';
    return base.replace(queryParameters: params);
  }

  @override
  Uri? searchUrl(Uri base, String query) {
    if (query.trim().isEmpty) return null;
    final params = Map<String, String>.from(base.queryParameters);
    params['q'] = query.trim();
    params.remove('page');
    return base.replace(queryParameters: params);
  }
}
