import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/sources/demo_source_adapter.dart';
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

class FakeBackend implements SecureCredentialBackend {
  final Map<String, String> keys = {};

  @override
  Future<void> write(String key, String value) async {
    keys[key] = value;
  }

  @override
  Future<String?> read(String key) async => keys[key];

  @override
  Future<void> delete(String key) async {
    keys.remove(key);
  }
}

/// Adaptador que quebra no parse: prova o isolamento do servico.
class ThrowingAdapter extends SourceAdapter {
  const ThrowingAdapter();

  @override
  String get id => 'throw.test';

  @override
  bool canHandle(Uri uri) => uri.host == 'throw.invalid';

  @override
  Future<Map<String, String>> headersFor(
    Uri uri,
    SourceCredentialStore credentials,
  ) async =>
      const {};

  @override
  SourceCatalogPage parseCatalog(String body) =>
      throw StateError('defeito no adaptador');

  @override
  manifestFor(String url, int itemCount) =>
      throw UnimplementedError();
}

Map<String, Object?> demoEntry({
  String id = 'd1',
  String name = 'Demo Um',
  Object? poster = 'https://cdn.demo.invalid/d1.jpg',
  Object? length = 90,
  Object? renditions,
}) =>
    {
      'video_id': id,
      'name': name,
      'file': 'https://cdn.demo.invalid/$id.mp4',
      if (poster != null) 'poster': poster,
      if (length != null) 'length': length,
      'renditions': renditions ??
          [
            {'label': '720p', 'file': 'https://cdn.demo.invalid/${id}_720.mp4'},
          ],
    };

String demoBody({
  List<Object?>? results,
  int page = 1,
  int totalPages = 1,
}) =>
    jsonEncode({
      'results': results ??
          [
            demoEntry(),
            demoEntry(id: 'd2', name: 'Demo Dois'),
          ],
      'page': page,
      'total_pages': totalPages,
    });

const demoUrl = 'https://api.demo.invalid/catalogo';
const demoSearchUrl = 'https://api.demo.invalid/catalogo?q=dois';

LocalAddonService demoService(Map<String, String> bodies) =>
    LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: FakeAddonFetcher(bodies),
      adapters: const [DemoSourceAdapter()],
    );

void main() {
  group('registro de adaptadores', () {
    test('demo casa .invalid; resto cai no generico', () {
      const adapters = [DemoSourceAdapter()];
      expect(
        SourceAdapters.forUrl('https://api.demo.invalid/c', adapters),
        isA<DemoSourceAdapter>(),
      );
      expect(
        SourceAdapters.forUrl('https://demo.invalid/c', adapters),
        isA<DemoSourceAdapter>(),
      );
      expect(
        SourceAdapters.forUrl('https://feeds.exemplo.com/c', adapters),
        isNull,
      );
      expect(SourceAdapters.forUrl('nao-url', adapters), isNull);
    });

    test('primeiro que casa vence', () {
      const adapters = [ThrowingAdapter(), DemoSourceAdapter()];
      expect(
        SourceAdapters.forUrl('https://throw.invalid/c', adapters),
        isA<ThrowingAdapter>(),
      );
    });
  });

  group('DemoSourceAdapter parse', () {
    const adapter = DemoSourceAdapter();

    test('mapeia tudo: poster, duracao, qualidades', () {
      final page = adapter.parseCatalog(demoBody());
      expect(page.items, hasLength(2));
      expect(page.hasMore, isFalse);
      final first = page.items.first;
      expect(first.id, 'd1');
      expect(first.title, 'Demo Um');
      expect(first.sourceUrl, 'https://cdn.demo.invalid/d1.mp4');
      expect(first.duration, const Duration(seconds: 90));
      expect(first.thumbnailUrl, 'https://cdn.demo.invalid/d1.jpg');
      expect(first.qualities, hasLength(1));
      expect(first.qualities.first.label, '720p');
    });

    test('paginacao do servidor sinaliza hasMore', () {
      final page =
          adapter.parseCatalog(demoBody(page: 1, totalPages: 3));
      expect(page.hasMore, isTrue);
      final last =
          adapter.parseCatalog(demoBody(page: 3, totalPages: 3));
      expect(last.hasMore, isFalse);
    });

    test('entradas invalidas pulam; vazio ok', () {
      final page = adapter.parseCatalog(demoBody(results: [
        demoEntry(),
        {'video_id': 'ruim'},
        'texto',
        {'video_id': 'x', 'name': 'Y', 'file': 'ftp://x/y'},
      ]));
      expect(page.items.map((e) => e.id), ['d1']);
      expect(adapter.parseCatalog(demoBody(results: [])).items, isEmpty);
    });

    test('envelope fora do formato rejeita', () {
      for (final bad in [
        'nao-json',
        '{"items": []}',
        '{"results": "x"}',
        '[]',
        demoBody(results: [
          {'video_id': 'ruim'}
        ]),
      ]) {
        expect(
          () => adapter.parseCatalog(bad),
          throwsA(isA<AddonError>().having(
              (e) => e.code, 'code', 'addon.invalid-manifest')),
          reason: bad,
        );
      }
    });

    test('construtores de pagina e busca', () {
      final base = Uri.parse(demoUrl);
      expect(adapter.pageUrl(base, 2)?.toString(),
          'https://api.demo.invalid/catalogo?page=2');
      expect(adapter.pageUrl(base, 0), isNull);
      expect(adapter.searchUrl(base, 'dois')?.toString(), demoSearchUrl);
      expect(adapter.searchUrl(base, '  '), isNull);
    });

    test('manifesto sintetizado e sem auth', () async {
      final manifest = adapter.manifestFor(demoUrl, 2);
      expect(manifest.id, 'demo.source');
      expect(manifest.catalogUrl, demoUrl);
      expect(manifest.permissions, ['catalog.read', 'playback.open']);
      expect(
        await adapter.headersFor(
            Uri.parse(demoUrl), InMemoryCredentialStore()),
        isEmpty,
      );
    });
  });

  group('servico com adaptador', () {
    test('catalogo vem mapeado; resolve leva poster', () async {
      final service = demoService({demoUrl: demoBody()});
      final preview = await service.previewSource(demoUrl);
      expect(preview.manifest.id, 'demo.source');
      expect(preview.feedItemCount, 2);
      expect(preview.feedSample, ['Demo Um', 'Demo Dois']);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('demo.source');

      final catalog = await service.getCatalog('demo.source');
      expect(catalog, hasLength(2));
      expect(catalog.first.thumbnailUrl,
          'https://cdn.demo.invalid/d1.jpg');
      final media =
          await service.resolvePlayback('demo.source', catalog.first);
      expect(media.source, 'https://cdn.demo.invalid/d1.mp4');
      expect(media.metadata['posterUrl'], 'https://cdn.demo.invalid/d1.jpg');
    });

    test('busca usa o servidor do adaptador', () async {
      final service = demoService({
        demoUrl: demoBody(),
        demoSearchUrl: demoBody(results: [
          demoEntry(id: 'd2', name: 'Demo Dois'),
        ]),
      });
      final preview = await service.previewSource(demoUrl);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('demo.source');

      final found = await service.search('demo.source', 'dois');
      expect(found.map((e) => e.id), ['d2']);
    });

    test('generico segue quando nenhum adaptador casa', () async {
      final service = demoService({
        'https://feeds.exemplo.com/c.json': jsonEncode({
          'items': [
            {
              'id': 'g1',
              'title': 'Generico',
              'sourceUrl': 'https://cdn.exemplo.com/g1.mp4',
            }
          ]
        }),
      });
      final preview =
          await service.previewSource('https://feeds.exemplo.com/c.json');
      expect(preview.manifest.id, startsWith('feed.'));
      await service.install(preview.manifest, originTrusted: false);
      await service.enable(preview.manifest.id);
      final catalog = await service.getCatalog(preview.manifest.id);
      expect(catalog.single.title, 'Generico');
    });

    test('defeito do adaptador isola sem vazar excecao', () async {
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: const FakeAddonFetcher(
            {'https://throw.invalid/c': '{"results": []}'}),
        adapters: const [ThrowingAdapter()],
      );
      // Instala direto: a previa quebraria no parse do stub.
      const manifest = AddonManifest(
        id: 'throw.source',
        name: 'Throw',
        version: '1.0.0',
        author: 'Teste',
        description: 'Stub que quebra no parse.',
        icon: 'rss_feed',
        homepage: 'https://throw.invalid',
        repository: 'teste',
        permissions: ['catalog.read'],
        supportedPlatforms: ['windows', 'linux', 'macos', 'android'],
        contentTypes: ['video'],
        catalogUrl: 'https://throw.invalid/c',
        legalNotice: 'Teste.',
      );
      await service.install(manifest, originTrusted: false);
      await service.enable('throw.source');
      expect(await service.getCatalog('throw.source'), isEmpty);
      expect(service.getStatus('throw.source'), AddonState.error);
    });

    test('atualizar e editar passam pelo adaptador', () async {
      final bodies = {
        demoUrl: demoBody(),
        'https://api.demo.invalid/outro': demoBody(results: [
          demoEntry(id: 'd9', name: 'Demo Nove'),
        ]),
      };
      final service = demoService(bodies);
      final preview = await service.previewSource(demoUrl);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable('demo.source');
      expect(await service.refreshSource('demo.source'), 2);

      // Outro path, mesmo host: mantem ativo.
      await service.updateSourceUrl(
          'demo.source', 'https://api.demo.invalid/outro');
      expect(service.getStatus('demo.source'), AddonState.active);
      final catalog = await service.getCatalog('demo.source');
      expect(catalog.single.id, 'd9');
    });
  });

  group('credenciais por fonte', () {
    test('memoria: salva, le, sobrescreve, apaga', () async {
      final store = InMemoryCredentialStore();
      expect(await store.read('demo.source'), isNull);
      await store.save('demo.source', 'segredo-1');
      expect(await store.read('demo.source'), 'segredo-1');
      await store.save('demo.source', 'segredo-2');
      expect(await store.read('demo.source'), 'segredo-2');
      await store.delete('demo.source');
      expect(await store.read('demo.source'), isNull);
      await store.delete('demo.source');
    });

    test('loja segura prefixa chaves no backend', () async {
      final backend = FakeBackend();
      final store = SecureCredentialStore(backend);
      await store.save('demo.source', 's3cr3t');
      expect(backend.keys, {'player.source.demo.source': 's3cr3t'});
      expect(await store.read('demo.source'), 's3cr3t');
      await store.delete('demo.source');
      expect(backend.keys, isEmpty);
      expect(await store.read('demo.source'), isNull);
    });
  });
}
