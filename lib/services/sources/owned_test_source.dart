import 'dart:convert';

import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/sources/source_adapter.dart';
import 'package:player/services/sources/source_credentials.dart';

/// Fonte propria de teste (Fase 2): feed JSON sob controle do dono do
/// app, com videos publicos (dominio publico / Creative Commons /
/// licenciados para teste). Formato PROPRIO (prova que o adaptador
/// traduz), paginacao e busca no servidor, miniatura e qualidades
/// opcionais.
///
/// Host `.invalid` (RFC 2606): nunca resolve de verdade; os testes
/// injetam o corpo via [AddonFetcher] fake. Quando o feed for
/// hospedado no endereco definitivo, trocar [testHost] pelo host
/// real e registrar o adaptador na construcao do servico. Sem essa
/// troca, nada muda no app: o adaptador so atua nas URLs que casa.
///
/// Autenticacao OPCIONAL: com segredo guardado no cofre sob o id
/// [id], [headersFor] envia `Authorization: Bearer ...`; sem
/// segredo, o feed e publico e nenhum cabecalho sai. Segredos nunca
/// vao para URL, log, manifesto ou JSON.
class OwnedTestSourceAdapter extends SourceAdapter {
  const OwnedTestSourceAdapter();

  /// Host reservado de teste. Trocar pelo host real do feed quando
  /// ele for hospedado (ver `docs/FONTE_PROPRIA_TESTE.md`).
  static const testHost = 'owned.invalid';

  /// Host da validacao de smoke (Fase 2): feed temporario sob controle
  /// do dono. Nao e provider terceiro: e o proprio feed; o Mux segue
  /// sendo so um DADO (URL de midia) dentro dele, nunca um host
  /// reconhecido aqui.
  static const smokeHost =
      '8080-i3z7luqmkzuzszqjs7uy1-59e363bb.us4.manus.computer';

  @override
  String get id => 'owned.test';

  @override
  bool canHandle(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == testHost || host.endsWith('.$testHost')) return true;
    return host == smokeHost;
  }

  @override
  Future<Map<String, String>> headersFor(
    Uri uri,
    SourceCredentialStore credentials,
  ) async {
    final secret = (await credentials.read(id))?.trim();
    if (secret == null || secret.isEmpty) return const {};
    return {'Authorization': 'Bearer $secret'};
  }

  /// Envelopes proprios (dois formatos estritos do MESMO feed):
  /// documentado `{"feed": "player-teste/1", "catalog": [{"id",
  /// "title","stream","subtitle"?,"poster"?,"duration"?,
  /// "streams"?:[{"quality","url"}]}], "page"?:1, "pages"?:1}` e
  /// publicado `{"items": [{"id","title","url","description"?,
  /// "thumbnail"?,"duration"?,"qualities"?:[{"quality","url"}]}],
  /// "page"?:1, "pages"?:1}` (ver `docs/FONTE_PROPRIA_TESTE.md`).
  /// Entradas invalidas sao puladas; envelope fora do formato lanca.
  /// O feed e DADO: nada dele vira logica, path ou markup.
  @override
  SourceCatalogPage parseCatalog(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const AddonError.invalidManifest(
        'Catálogo próprio inválido: resposta não é um JSON.',
      );
    }
    if (decoded is! Map) {
      throw const AddonError.invalidManifest(
        'Catálogo próprio inválido: esperado um objeto JSON.',
      );
    }
    final map = decoded;
    if (map['catalog'] is List) {
      if (map['feed'] is! String) {
        throw const AddonError.invalidManifest(
          'Catálogo próprio inválido: esperado {"feed","catalog": [...]}.',
        );
      }
      return _pageFrom(
          map, (entry) => _itemFrom(Map<String, Object?>.from(entry)));
    }
    if (map['items'] is List) {
      return _pageFrom(
          map,
          (entry) =>
              _itemFrom(_normalizeSmoke(Map<String, Object?>.from(entry))));
    }
    throw const AddonError.invalidManifest(
      'Catálogo próprio inválido: esperado {"feed","catalog": [...]} '
      'ou {"items": [...]}.',
    );
  }

  /// Converte o item do formato publicado para as chaves do formato
  /// documentado e reaproveita a validacao estrita de [_itemFrom].
  /// Campos ausentes ou nulos sao omitidos (opcionais); tipos errados
  /// rejeitam o item inteiro na validacao.
  Map<String, Object?> _normalizeSmoke(Map<String, Object?> json) {
    return {
      'id': json['id'],
      'title': json['title'],
      'stream': json['url'],
      if (json['description'] != null) 'subtitle': json['description'],
      if (json['thumbnail'] != null) 'poster': json['thumbnail'],
      if (json['duration'] != null) 'duration': json['duration'],
      if (json['qualities'] != null) 'streams': json['qualities'],
    };
  }

  SourceCatalogPage _pageFrom(
    Map decoded,
    AddonCatalogItem Function(Map entry) parseItem,
  ) {
    final raw = (decoded['catalog'] is List
        ? decoded['catalog']
        : decoded['items']) as List;
    if (raw.length > 500) {
      throw const AddonError.invalidManifest(
        'Catálogo grande demais (limite de 500 itens).',
      );
    }
    final items = <AddonCatalogItem>[];
    for (final entry in raw) {
      try {
        if (entry is! Map) continue;
        items.add(parseItem(entry));
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
    final pages = _asInt(decoded['pages'], 1);
    return SourceCatalogPage(items: items, hasMore: page < pages);
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int && value > 0) return value;
    return fallback;
  }

  AddonCatalogItem _itemFrom(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final stream = json['stream'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.isEmpty ||
        stream is! String ||
        !isSupportedUrl(stream)) {
      throw const AddonError.invalidManifest(
        'Item do catálogo próprio inválido.',
      );
    }
    final subtitle = json['subtitle'];
    if (subtitle != null && (subtitle is! String || subtitle.isEmpty)) {
      throw const AddonError.invalidManifest(
        'Legenda do item próprio inválida.',
      );
    }
    final poster = json['poster'];
    if (poster != null && (poster is! String || !isSupportedUrl(poster))) {
      throw const AddonError.invalidManifest(
        'Miniatura do item próprio inválida.',
      );
    }
    Duration? duration;
    final length = json['duration'];
    if (length != null) {
      final seconds =
          length is int ? length : (length is double ? length.round() : -1);
      if (seconds < 0) {
        throw const AddonError.invalidManifest(
          'Duração do item próprio inválida.',
        );
      }
      duration = Duration(seconds: seconds);
    }
    final qualities = <SourceQuality>[];
    final streams = json['streams'];
    if (streams != null) {
      if (streams is! List) {
        throw const AddonError.invalidManifest(
          'Qualidades do item próprio inválidas.',
        );
      }
      for (final rendition in streams) {
        if (rendition is! Map) {
          throw const AddonError.invalidManifest(
            'Qualidade do item próprio inválida.',
          );
        }
        final map = Map<String, Object?>.from(rendition);
        final quality = map['quality'];
        final url = map['url'];
        if (quality is! String ||
            quality.isEmpty ||
            url is! String ||
            !isSupportedUrl(url)) {
          throw const AddonError.invalidManifest(
            'Qualidade do item próprio inválida.',
          );
        }
        qualities.add(SourceQuality(
          id: quality,
          label: quality,
          sourceUrl: url,
        ));
      }
    }
    return AddonCatalogItem(
      id: id,
      title: title,
      subtitle: subtitle as String?,
      sourceUrl: stream,
      duration: duration,
      thumbnailUrl: poster as String?,
      qualities: List.unmodifiable(qualities),
    );
  }

  @override
  AddonManifest manifestFor(String url, int itemCount) {
    return AddonManifest(
      id: 'owned.test',
      name: 'Fonte Própria (teste)',
      version: '1.0.0',
      author: 'Dono do app',
      description: 'Fonte própria de teste com $itemCount '
          '${itemCount == 1 ? 'item' : 'itens'} (feed sob controle).',
      icon: 'rss_feed',
      homepage: 'https://owned.invalid',
      repository: url,
      permissions: const ['catalog.read', 'playback.open'],
      supportedPlatforms: const ['windows', 'linux', 'macos', 'android'],
      contentTypes: const ['video'],
      catalogUrl: url,
      legalNotice: 'Fonte própria para testes. Conteúdo público ou licenciado.',
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
