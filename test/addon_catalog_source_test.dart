import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/local_addon_service.dart';

/// Fake programavel: URL conhecida devolve corpo, o resto falha.
class FakeAddonFetcher extends AddonFetcher {
  const FakeAddonFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url, {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

const _feedUrl = 'https://fonte.exemplo.com/catalogo.json';

String _feed(List<Object?> items) => jsonEncode({'items': items});

Map<String, Object?> _item({
  Object? id = 'v1',
  Object? title = 'Video Um',
  Object? subtitle = 'Serie A',
  Object? sourceUrl = 'https://cdn.exemplo.com/v1.mp4',
  Object? duration = 90,
}) =>
    {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'sourceUrl': sourceUrl,
      'duration': duration,
    };

LocalAddonService _service({AddonFetcher fetcher = const FakeAddonFetcher({})}) =>
    LocalAddonService(InMemoryLocalStore(), platform: 'windows', fetcher: fetcher);

Future<LocalAddonService> _installed({String? catalogUrl}) async {
  final service = _service(
    fetcher: FakeAddonFetcher({
      _feedUrl: _feed([
        _item(),
        _item(id: 'v2', title: 'Video Dois', duration: 120),
      ]),
    }),
  );
  final json = demoManifestJson();
  if (catalogUrl != null) json['catalogUrl'] = catalogUrl;
  await service.install(await service.validate(json), originTrusted: true);
  await service.enable('demo.catalogo');
  return service;
}

void main() {
  group('AddonCatalogItem.fromJson', () {
    test('valido passa com duracao', () {
      final item = AddonCatalogItem.fromJson(_item());
      expect(item.id, 'v1');
      expect(item.title, 'Video Um');
      expect(item.subtitle, 'Serie A');
      expect(item.sourceUrl, 'https://cdn.exemplo.com/v1.mp4');
      expect(item.duration, const Duration(seconds: 90));
    });

    test('tabela de rejeicao', () {
      final bad = [
        _item(id: null),
        _item(id: ''),
        _item(id: 42),
        _item(title: null),
        _item(title: ''),
        _item(sourceUrl: null),
        _item(sourceUrl: 'ftp://x/y.mp4'),
        _item(sourceUrl: 'nao-url'),
        _item(subtitle: 42),
        _item(duration: -5),
        _item(duration: 'noventa'),
      ];
      for (final json in bad) {
        expect(
          () => AddonCatalogItem.fromJson(json),
          throwsA(isA<AddonError>().having(
              (e) => e.code, 'code', 'addon.invalid-manifest')),
          reason: '$json',
        );
      }
    });
  });

  group('parseCatalogItems', () {
    test('envelope valido', () {
      final items = parseCatalogItems(_feed([_item(), _item(id: 'v2')]));
      expect(items, hasLength(2));
      expect(items.first.title, 'Video Um');
    });

    test('tabela de rejeicao', () {
      final bad = [
        'nao-json',
        '{"items": "x"}',
        '{"outro": []}',
        '[]',
        _feed([
          {'id': 'v1'}
        ]),
      ];
      for (final body in bad) {
        expect(
          () => parseCatalogItems(body),
          throwsA(isA<AddonError>().having(
              (e) => e.code, 'code', 'addon.invalid-manifest')),
          reason: body,
        );
      }
    });

    test('item invalido nao invalida os validos (6.1.1)', () {
      final items = parseCatalogItems(_feed([
        _item(),
        {'id': 'ruim'},
        'texto',
        _item(id: 'v2', title: 'Video Dois'),
      ]));
      expect(items.map((e) => e.id), ['v1', 'v2']);
    });

    test('feed vazio e valido, sem item valido isola', () {
      expect(parseCatalogItems(_feed([])), isEmpty);
      expect(
        () => parseCatalogItems(_feed([
          {'id': 'ruim'},
        ])),
        throwsA(isA<AddonError>()),
      );
    });

    test('acima de 500 itens rejeita', () {
      final items = List.generate(501, (i) => _item(id: 'v$i'));
      expect(
        () => parseCatalogItems(_feed(items)),
        throwsA(isA<AddonError>()),
      );
    });
  });

  group('AddonManifest catalogUrl', () {
    test('round-trip valido', () {
      final json = demoManifestJson()..['catalogUrl'] = _feedUrl;
      final manifest = AddonManifest.fromMap(json);
      expect(manifest.catalogUrl, _feedUrl);
      expect(AddonManifest.fromMap(manifest.toMap()).catalogUrl, _feedUrl);
    });

    test('ausente e vazio viram null', () {
      expect(
        AddonManifest.fromMap(demoManifestJson()).catalogUrl,
        isNull,
      );
      final json = demoManifestJson()..['catalogUrl'] = '  ';
      expect(AddonManifest.fromMap(json).catalogUrl, isNull);
    });

    test('invalido rejeita', () {
      for (final value in ['ftp://x', 'nao-url', 42]) {
        final json = demoManifestJson()..['catalogUrl'] = value;
        expect(
          () => AddonManifest.fromMap(json),
          throwsA(isA<AddonError>()),
          reason: '$value',
        );
      }
    });
  });

  group('LocalAddonService feed remoto', () {
    test('catalogUrl serve itens remotos', () async {
      final service = await _installed(catalogUrl: _feedUrl);
      final catalog = await service.getCatalog('demo.catalogo');
      expect(catalog, hasLength(2));
      expect(catalog.first.title, 'Video Um');
      // Resolucao segue intacta sobre item remoto.
      final media =
          await service.resolvePlayback('demo.catalogo', catalog.first);
      expect(media.source, 'https://cdn.exemplo.com/v1.mp4');
      expect(media.metadata['addonId'], 'demo.catalogo');
    });

    test('busca filtra o feed remoto', () async {
      final service = await _installed(catalogUrl: _feedUrl);
      final found = await service.search('demo.catalogo', 'dois');
      expect(found, hasLength(1));
      expect(found.first.id, 'v2');
    });

    test('falha de rede isola e devolve vazio', () async {
      final service =
          await _installed(catalogUrl: 'https://fonte.exemplo.com/off.json');
      expect(
          await service.getCatalog('demo.catalogo'), isEmpty);
      expect(service.getStatus('demo.catalogo'), AddonState.error);
    });

    test('corpo malformado isola e devolve vazio', () async {
      final bad = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: const FakeAddonFetcher({_feedUrl: 'nao-json'}),
      );
      final json = demoManifestJson()..['catalogUrl'] = _feedUrl;
      await bad.install(await bad.validate(json), originTrusted: true);
      await bad.enable('demo.catalogo');
      expect(await bad.getCatalog('demo.catalogo'), isEmpty);
      expect(bad.getStatus('demo.catalogo'), AddonState.error);
    });

    test('sem feed mantem o embutido', () async {
      final service = await _installed();
      expect(await service.getCatalog('demo.catalogo'), isNotEmpty);
    });
  });

  group('paginacao', () {
    test('fatia e sinaliza hasMore', () {
      final all = List.generate(
        45,
        (i) => AddonCatalogItem(
          id: 'v$i',
          title: 'V $i',
          sourceUrl: 'https://cdn.exemplo.com/v$i.mp4',
        ),
      );
      final p1 = paginateCatalogItems(all, page: 1, pageSize: 20);
      expect(p1.items, hasLength(20));
      expect(p1.totalItems, 45);
      expect(p1.hasMore, isTrue);
      final p3 = paginateCatalogItems(all, page: 3, pageSize: 20);
      expect(p3.items, hasLength(5));
      expect(p3.hasMore, isFalse);
      final p9 = paginateCatalogItems(all, page: 9, pageSize: 20);
      expect(p9.items, isEmpty);
      expect(p9.hasMore, isFalse);
    });

    test('contrato pagina o servico', () async {
      final service = await _installed(catalogUrl: _feedUrl);
      final page = await service.getCatalogPage('demo.catalogo',
          page: 2, pageSize: 1);
      expect(page.items, hasLength(1));
      expect(page.items.first.id, 'v2');
      expect(page.totalItems, 2);
      expect(page.hasMore, isFalse);
      final found =
          await service.searchPage('demo.catalogo', 'video', pageSize: 1);
      expect(found.items, hasLength(1));
      expect(found.totalItems, 2);
      expect(found.hasMore, isTrue);
    });
  });
}
