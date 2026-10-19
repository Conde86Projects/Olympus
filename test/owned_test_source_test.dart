import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/sources/owned_test_source.dart';
import 'package:player/services/sources/source_adapter.dart';
import 'package:player/services/sources/source_credentials.dart';

class FakeAddonFetcher extends AddonFetcher {
  const FakeAddonFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

Map<String, Object?> ownedEntry({
  String id = 't1',
  String name = 'Tears of Steel',
  Object? subtitle = 'Blender Foundation (CC-BY)',
  Object? poster = 'https://picsum.photos/seed/tos/640/360',
  Object? duration = 734,
  Object? streams,
  String? stream,
}) =>
    {
      'id': id,
      'title': name,
      'stream': stream ?? 'https://cdn.owned.invalid/$id.m3u8',
      if (subtitle != null) 'subtitle': subtitle,
      if (poster != null) 'poster': poster,
      if (duration != null) 'duration': duration,
      'streams': streams ??
          [
            {
              'quality': 'HLS adaptativo',
              'url': 'https://cdn.owned.invalid/${id}_a.m3u8'
            },
            {
              'quality': 'MP4 direto',
              'url': 'https://cdn.owned.invalid/$id.mp4'
            },
          ],
    };

String ownedBody({
  List<Object?>? catalog,
  int page = 1,
  int pages = 1,
}) =>
    jsonEncode({
      'feed': 'player-teste/1',
      'catalog': catalog ??
          [
            ownedEntry(),
            ownedEntry(
              id: 't2',
              name: 'Big Buck Bunny',
              stream: 'https://cdn.owned.invalid/t2.mp4',
            ),
          ],
      'page': page,
      'pages': pages,
    });

const ownedUrl = 'https://owned.invalid/catalogo.json';
const ownedSearchUrl = 'https://owned.invalid/catalogo.json?q=buck';

LocalAddonService ownedService(
  Map<String, String> bodies, {
  SourceCredentialStore? credentials,
}) =>
    LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: FakeAddonFetcher(bodies),
      adapters: const [OwnedTestSourceAdapter()],
      credentials: credentials,
    );

const smokeFeedUrl =
    'https://8080-i3z7luqmkzuzszqjs7uy1-59e363bb.us4.manus.computer/feed.json';

Map<String, Object?> smokeEntry() => {
      'id': 'mux-smoke',
      'title': 'Teste HLS — Mux x36xhzz',
      'description':
          'Stream público de demonstração usado temporariamente para validar o player Olympus.',
      'url': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      'duration': 634,
      'thumbnail': null,
      'qualities': [],
    };

String smokeBody(List<Object?> items) =>
    jsonEncode({'page': 1, 'pages': 1, 'items': items});

// Corpo byte a byte no formato publicado (oraculo independente do
// helper acima): o teste de mapeamento usa esta constante.
const smokeFeedBody =
    '{"page":1,"pages":1,"items":[{"id":"mux-smoke","title":"Teste HLS — Mux x36xhzz","description":"Stream público de demonstração usado temporariamente para validar o player Olympus.","url":"https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8","duration":634,"thumbnail":null,"qualities":[]}]}';

void main() {
  group('formato publicado (smoke)', () {
    const adapter = OwnedTestSourceAdapter();

    test('casa o host do feed; Mux nunca e fonte propria', () {
      const adapters = [OwnedTestSourceAdapter()];
      expect(
        SourceAdapters.forUrl(smokeFeedUrl, adapters),
        isA<OwnedTestSourceAdapter>(),
      );
      expect(
        SourceAdapters.forUrl(
            'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', adapters),
        isNull,
      );
    });

    test('corpo real publicado mapeia o item mux-smoke', () {
      final page = adapter.parseCatalog(smokeFeedBody);
      expect(page.items, hasLength(1));
      expect(page.hasMore, isFalse);
      final item = page.items.single;
      expect(item.id, 'mux-smoke');
      expect(item.title, 'Teste HLS — Mux x36xhzz');
      expect(item.subtitle,
          'Stream público de demonstração usado temporariamente para validar o player Olympus.');
      expect(
          item.sourceUrl, 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');
      expect(item.duration, const Duration(seconds: 634));
      expect(item.thumbnailUrl, isNull);
      expect(item.qualities, isEmpty);
    });

    test('itens publicados invalidos pulam; vazio ok', () {
      final page = adapter.parseCatalog(smokeBody([
        smokeEntry(),
        {'id': 'ruim'},
        'texto',
        {'id': 'x', 'title': 'Y', 'url': 'ftp://x/y'},
        {
          'id': 'z',
          'title': 'Z',
          'url': 'https://cdn.owned.invalid/z.mp4',
          'thumbnail': 42
        },
      ]));
      expect(page.items.map((e) => e.id), ['mux-smoke']);
      expect(adapter.parseCatalog(smokeBody([])).items, isEmpty);
    });

    test('envelope publicado fora do formato rejeita', () {
      for (final bad in [
        '{"items":"x"}',
        '{"items":[{"id":"ruim"}]}',
        '{"items":[{"id":"x","title":"Y"}]}',
        '{"catalog":"x"}',
      ]) {
        expect(
          () => adapter.parseCatalog(bad),
          throwsA(isA<AddonError>()
              .having((e) => e.code, 'code', 'addon.invalid-manifest')),
          reason: bad,
        );
      }
    });

    test('previa do feed publicado instala como fonte propria', () async {
      final service = ownedService({smokeFeedUrl: smokeFeedBody});
      final preview = await service.previewSource(smokeFeedUrl);
      expect(preview.manifest.id, 'owned.test');
      expect(preview.feedItemCount, 1);
      expect(preview.feedSample, ['Teste HLS — Mux x36xhzz']);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('owned.test');
      final catalog = await service.getCatalog('owned.test');
      expect(catalog.single.sourceUrl,
          'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');
    });
  });

  group('registro do adaptador proprio', () {
    test('casa o host reservado e subdominios; resto nao', () {
      const adapters = [OwnedTestSourceAdapter()];
      expect(
        SourceAdapters.forUrl('https://owned.invalid/catalogo.json', adapters),
        isA<OwnedTestSourceAdapter>(),
      );
      expect(
        SourceAdapters.forUrl('https://api.owned.invalid/c.json', adapters),
        isA<OwnedTestSourceAdapter>(),
      );
      expect(
        SourceAdapters.forUrl('https://feeds.exemplo.com/c.json', adapters),
        isNull,
      );
      expect(SourceAdapters.forUrl('nao-url', adapters), isNull);
    });
  });

  group('OwnedTestSourceAdapter parse', () {
    const adapter = OwnedTestSourceAdapter();

    test('catalogo: mapeia tudo (legenda, poster, duracao, qualidades)', () {
      final page = adapter.parseCatalog(ownedBody());
      expect(page.items, hasLength(2));
      expect(page.hasMore, isFalse);
      final first = page.items.first;
      expect(first.id, 't1');
      expect(first.title, 'Tears of Steel');
      expect(first.subtitle, 'Blender Foundation (CC-BY)');
      expect(first.sourceUrl, 'https://cdn.owned.invalid/t1.m3u8');
      expect(first.duration, const Duration(seconds: 734));
      expect(first.thumbnailUrl, 'https://picsum.photos/seed/tos/640/360');
      expect(first.qualities.map((q) => q.label),
          ['HLS adaptativo', 'MP4 direto']);
    });

    test('HLS e MP4 convivem no mesmo catalogo', () {
      final page = adapter.parseCatalog(ownedBody());
      expect(page.items.first.sourceUrl.endsWith('.m3u8'), isTrue);
      expect(page.items.last.sourceUrl.endsWith('.mp4'), isTrue);
    });

    test('paginacao do servidor sinaliza hasMore', () {
      expect(
          adapter.parseCatalog(ownedBody(page: 1, pages: 3)).hasMore, isTrue);
      expect(
          adapter.parseCatalog(ownedBody(page: 3, pages: 3)).hasMore, isFalse);
    });

    test('entradas invalidas pulam; feed vazio ok', () {
      final page = adapter.parseCatalog(ownedBody(catalog: [
        ownedEntry(),
        {'id': 'ruim'},
        'texto',
        {'id': 'x', 'title': 'Y', 'stream': 'ftp://x/y'},
        {
          'id': 'z',
          'title': 'Z',
          'stream': 'https://cdn.owned.invalid/z.mp4',
          'poster': 'nao-url'
        },
        {
          'id': 'w',
          'title': 'W',
          'stream': 'https://cdn.owned.invalid/w.mp4',
          'duration': -3
        },
        {
          'id': 'v',
          'title': 'V',
          'stream': 'https://cdn.owned.invalid/v.mp4',
          'streams': 'x'
        },
      ]));
      expect(page.items.map((e) => e.id), ['t1']);
      expect(adapter.parseCatalog(ownedBody(catalog: [])).items, isEmpty);
    });

    test('envelope fora do formato rejeita (erro, nao item parcial)', () {
      // '{"items": []}' e '{"catalog": ...}' vazio sao feeds vazios
      // validos (cobertos no teste de vazio), nao rejeicao.
      for (final bad in [
        'nao-json',
        '{"catalog": "x"}',
        '{"outro": []}',
        '[]',
        ownedBody(catalog: [
          {'id': 'ruim'}
        ]),
      ]) {
        expect(
          () => adapter.parseCatalog(bad),
          throwsA(isA<AddonError>()
              .having((e) => e.code, 'code', 'addon.invalid-manifest')),
          reason: bad,
        );
      }
    });

    test('construtores de pagina e busca', () {
      final base = Uri.parse(ownedUrl);
      expect(adapter.pageUrl(base, 2)?.toString(),
          'https://owned.invalid/catalogo.json?page=2');
      expect(adapter.pageUrl(base, 0), isNull);
      expect(adapter.searchUrl(base, 'buck')?.toString(), ownedSearchUrl);
      expect(adapter.searchUrl(base, '  '), isNull);
    });

    test('manifesto sintetizado para a revisao humana', () {
      final manifest = adapter.manifestFor(ownedUrl, 2);
      expect(manifest.id, 'owned.test');
      expect(manifest.catalogUrl, ownedUrl);
      expect(manifest.permissions, ['catalog.read', 'playback.open']);
    });

    test('auth opcional: sem segredo nao sai cabecalho', () async {
      expect(
        await adapter.headersFor(
            Uri.parse(ownedUrl), InMemoryCredentialStore()),
        isEmpty,
      );
    });

    test('auth opcional: com segredo no cofre sai Bearer; valor nao vaza',
        () async {
      final credentials = InMemoryCredentialStore();
      await credentials.save('owned.test', 'chave-abc');
      final headers =
          await adapter.headersFor(Uri.parse(ownedUrl), credentials);
      expect(headers, {'Authorization': 'Bearer chave-abc'});
      final manifest = adapter.manifestFor(ownedUrl, 1);
      final exposed = [
        manifest.id,
        manifest.name,
        manifest.description,
        manifest.homepage,
        manifest.repository,
        manifest.catalogUrl,
        manifest.legalNotice,
      ].whereType<String>().join('|');
      expect(exposed.contains('chave-abc'), isFalse);
    });
  });

  group('servico com adaptador proprio', () {
    test('catalogo vem mapeado; resolve leva poster', () async {
      final service = ownedService({ownedUrl: ownedBody()});
      final preview = await service.previewSource(ownedUrl);
      expect(preview.manifest.id, 'owned.test');
      expect(preview.feedItemCount, 2);
      expect(preview.feedSample, ['Tears of Steel', 'Big Buck Bunny']);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('owned.test');

      final catalog = await service.getCatalog('owned.test');
      expect(catalog, hasLength(2));
      expect(
          catalog.first.thumbnailUrl, 'https://picsum.photos/seed/tos/640/360');
      final media = await service.resolvePlayback('owned.test', catalog.first);
      expect(media.source, 'https://cdn.owned.invalid/t1.m3u8');
      expect(media.metadata['posterUrl'],
          'https://picsum.photos/seed/tos/640/360');
    });

    test('busca usa o servidor do adaptador', () async {
      final service = ownedService({
        ownedUrl: ownedBody(),
        ownedSearchUrl: ownedBody(catalog: [
          ownedEntry(
            id: 't2',
            name: 'Big Buck Bunny',
            stream: 'https://cdn.owned.invalid/t2.mp4',
          ),
        ]),
      });
      final preview = await service.previewSource(ownedUrl);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('owned.test');

      final found = await service.search('owned.test', 'buck');
      expect(found.map((e) => e.id), ['t2']);
    });

    test('falha de rede isola a fonte sem vazar excecao', () async {
      final service = ownedService({});
      const badUrl = 'https://owned.invalid/fora.json';
      expect(() => service.previewSource(badUrl), throwsA(isA<AddonError>()));
    });

    test('feed invalido na previa rejeita com motivo legivel', () async {
      final service = ownedService({ownedUrl: 'nao-json'});
      expect(
          () => service.previewSource(ownedUrl),
          throwsA(isA<AddonError>()
              .having((e) => e.code, 'code', 'addon.invalid-manifest')));
    });
  });
}
