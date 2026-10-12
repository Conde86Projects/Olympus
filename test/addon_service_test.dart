import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/local_addon_service.dart';

AddonCatalogItem demoItem() => demoCatalog().first;

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

LocalAddonService _service({
  String platform = 'windows',
  AddonFetcher fetcher = const FakeAddonFetcher({}),
}) =>
    LocalAddonService(InMemoryLocalStore(),
        platform: platform, fetcher: fetcher);

Future<void> _install(LocalAddonService service) async {
  final manifest =
      await service.validate(demoManifestJson());
  await service.install(manifest, originTrusted: false);
}

void main() {
  group('LocalAddonService ciclo de vida', () {
    test('instala desativado e persiste entre cargas', () async {
      final store = InMemoryLocalStore();
      final first = LocalAddonService(store, platform: 'windows');
      await first.load();
      await first.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: false,
      );
      expect(first.getStatus('demo.catalogo'), AddonState.inactive);

      final second = LocalAddonService(store, platform: 'windows');
      await second.load();
      expect(second.addons, hasLength(1));
      expect(second.findById('demo.catalogo')!.state, AddonState.inactive);
    });

    test('duplicado é rejeitado sem gravar', () async {
      final service = _service();
      await _install(service);
      await expectLater(
        () => _install(service),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.already-installed')),
      );
      expect(service.addons, hasLength(1));
    });

    test('manifesto inválido é rejeitado na validação', () async {
      final service = _service();
      await expectLater(
        () => service.validate({'id': 'x'}),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.addons, isEmpty);
    });

    test('fetchManifest baixa e valida via fetcher injetado', () async {
      final service = _service(
        fetcher: FakeAddonFetcher({
          'https://exemplo.com/man.json':
              jsonEncode(demoManifestJson()),
        }),
      );
      final manifest = await service.fetchManifest(
        'https://exemplo.com/man.json',
      );
      expect(manifest.id, 'demo.catalogo');
      // Buscar não instala: nada muda no estado.
      expect(service.addons, isEmpty);
    });

    test('fetchManifest propaga falha de rede como AddonError', () async {
      final service = _service();
      await expectLater(
        () => service.fetchManifest('https://exemplo.com/x.json'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.fetch-failed')),
      );
      expect(service.addons, isEmpty);
    });

    test('fetchManifest rejeita corpo com manifesto inválido', () async {
      final service = _service(
        fetcher:
            const FakeAddonFetcher({'https://exemplo.com/x.json': '{}'}),
      );
      await expectLater(
        () => service.fetchManifest('https://exemplo.com/x.json'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.addons, isEmpty);
    });

    test('ativar e desativar alternam o estado', () async {
      final service = _service();
      await _install(service);
      await service.enable('demo.catalogo');
      expect(service.getStatus('demo.catalogo'), AddonState.active);
      await service.disable('demo.catalogo');
      expect(service.getStatus('demo.catalogo'), AddonState.inactive);
    });

    test('incompatível mantém desativado com motivo', () async {
      final service = _service(platform: 'android');
      final manifest = AddonManifest.fromMap(demoManifestJson()
        ..['supportedPlatforms'] = ['windows']);
      await service.install(manifest, originTrusted: true);
      await service.enable('demo.catalogo');
      final info = service.findById('demo.catalogo')!;
      expect(info.state, AddonState.inactive);
      expect(info.diagnostic, contains('compatível'));
    });

    test('remover apaga só o add-on', () async {
      final service = _service();
      await _install(service);
      await service.uninstall('demo.catalogo');
      expect(service.addons, isEmpty);
      expect(service.findById('demo.catalogo'), isNull);
    });

    test('id desconhecido falha de forma controlada', () async {
      final service = _service();
      expect(() => service.getStatus('ausente'),
          throwsA(isA<AddonError>().having(
              (e) => e.code, 'code', 'addon.not-found')));
      await expectLater(
        () => service.enable('ausente'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.not-found')));
    });

    test('catalogo e busca servem o demo quando ativo', () async {
      final service = _service();
      await _install(service);
      expect(await service.getCatalog('demo.catalogo'), isEmpty);

      await service.enable('demo.catalogo');
      final catalog = await service.getCatalog('demo.catalogo');
      expect(catalog.map((item) => item.title),
          ['Aurora Demo', 'Maré Demo']);

      final found = await service.search('demo.catalogo', 'maré');
      expect(found.map((item) => item.id), ['mare']);
      expect(await service.search('demo.catalogo', 'inexistente'), isEmpty);
      expect(await service.search('demo.catalogo', '   '), isEmpty);
    });

    test('resolucao monta a midia; desativado falha controlado', () async {
      final service = _service();
      await _install(service);
      await expectLater(
        () => service.resolvePlayback('demo.catalogo', demoItem()),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.disabled')),
      );

      await service.enable('demo.catalogo');
      final media =
          await service.resolvePlayback('demo.catalogo', demoItem());
      expect(media.title, 'Aurora Demo');
      expect(media.source, 'https://exemplo.com/demo/aurora.mp4');
      expect(media.sourceType, MediaSourceType.url);
    });

    test('defeito isola um add-on sem afetar o outro', () async {
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        faultyIds: const {'ruim.catalogo'},
      );
      for (final id in ['demo.catalogo', 'ruim.catalogo']) {
        await service.install(
          AddonManifest.fromMap(demoManifestJson(id: id)),
          originTrusted: false,
        );
        await service.enable(id);
      }

      expect(await service.getCatalog('ruim.catalogo'), isEmpty);
      final failed = service.findById('ruim.catalogo')!;
      expect(failed.state, AddonState.error);
      expect(failed.diagnostic, contains('catálogo'));

      await expectLater(
        () => service.resolvePlayback('ruim.catalogo', demoItem()),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unavailable')),
      );

      final healthy = await service.getCatalog('demo.catalogo');
      expect(healthy, hasLength(2));
      expect(service.getStatus('demo.catalogo'), AddonState.active);
    });

    test('entrada corrompida é ignorada na carga', () async {
      final store = InMemoryLocalStore();
      Map<String, Object?> entry(Map<String, Object?> manifest) => {
            'manifest': manifest,
            'state': 'inactive',
            'originTrusted': false,
            'installedAt': DateTime(2026, 1, 1).toIso8601String(),
          };
      await store.write('addons', {
        'items': [
          entry(demoManifestJson()),
          entry({'id': 'ruim'}),
        ],
      });
      final service = LocalAddonService(store, platform: 'windows');
      await service.load();
      expect(service.addons.map((a) => a.manifest.id), ['demo.catalogo']);
    });
  });

  group('LocalAddonService repositórios', () {
    test('cadastra, lista ordenado e persiste entre cargas', () async {
      final store = InMemoryLocalStore();
      final first = LocalAddonService(store, platform: 'windows');
      await first.addRepository(
        name: 'Zeta',
        originUrl: 'https://exemplo.com/z.json',
      );
      await first.addRepository(
        name: 'Alfa',
        originUrl: 'https://exemplo.com/a.json',
        trusted: true,
      );
      expect(
        first.repositories.map((r) => r.name),
        ['Alfa', 'Zeta'],
      );
      expect(first.repositories.first.trusted, isTrue);

      final second = LocalAddonService(store, platform: 'windows');
      await second.load();
      expect(
        second.repositories.map((r) => r.name),
        ['Alfa', 'Zeta'],
      );
    });

    test('endereço inválido é rejeitado sem gravar', () async {
      final service = _service();
      await expectLater(
        () => service.addRepository(
          name: 'Ruim',
          originUrl: 'não é url',
        ),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.repositories, isEmpty);
    });

    test('nome vazio é rejeitado sem gravar', () async {
      final service = _service();
      await expectLater(
        () => service.addRepository(
          name: '  ',
          originUrl: 'https://exemplo.com/a.json',
        ),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.repositories, isEmpty);
    });

    test('endereço duplicado é rejeitado', () async {
      final service = _service();
      await service.addRepository(
        name: 'Um',
        originUrl: 'https://exemplo.com/a.json',
      );
      await expectLater(
        () => service.addRepository(
          name: 'Dois',
          originUrl: 'https://exemplo.com/a.json',
        ),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.repo-exists')),
      );
      expect(service.repositories, hasLength(1));
    });

    test('remover apaga só o cadastro', () async {
      final service = _service();
      final repo = await service.addRepository(
        name: 'Um',
        originUrl: 'https://exemplo.com/a.json',
      );
      await service.removeRepository(repo.id);
      expect(service.repositories, isEmpty);
      await expectLater(
        () => service.removeRepository('inexistente'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.repo-not-found')),
      );
    });

    test('fetchRepoAddons lista manifestos via fetcher injetado', () async {
      final service = _service(
        fetcher: FakeAddonFetcher({
          'https://exemplo.com/repo.json': jsonEncode({
            'addons': [demoManifestJson()],
          }),
        }),
      );
      final repo = await service.addRepository(
        name: 'Demo',
        originUrl: 'https://exemplo.com/repo.json',
      );
      final manifests = await service.fetchRepoAddons(repo.id);
      expect(manifests.map((m) => m.id), ['demo.catalogo']);
    });

    test('fetchRepoAddons propaga falha de rede', () async {
      final service = _service();
      final repo = await service.addRepository(
        name: 'Demo',
        originUrl: 'https://exemplo.com/repo.json',
      );
      await expectLater(
        () => service.fetchRepoAddons(repo.id),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.fetch-failed')),
      );
    });

    test('fetchRepoAddons rejeita listagem malformada', () async {
      final service = _service(
        fetcher: const FakeAddonFetcher(
            {'https://exemplo.com/repo.json': '{"addons":{}}'}),
      );
      final repo = await service.addRepository(
        name: 'Demo',
        originUrl: 'https://exemplo.com/repo.json',
      );
      await expectLater(
        () => service.fetchRepoAddons(repo.id),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
    });

    test('clearAllData apaga instalados, repos e última alteração',
        () async {
      final store = InMemoryLocalStore();
      final service = LocalAddonService(store, platform: 'windows');
      await _install(service);
      await service.addRepository(
        name: 'Demo',
        originUrl: 'https://exemplo.com/repo.json',
      );
      await service.clearAllData();

      expect(service.addons, isEmpty);
      expect(service.repositories, isEmpty);

      final fresh = LocalAddonService(store, platform: 'windows');
      await fresh.load();
      expect(fresh.addons, isEmpty);
      expect(fresh.repositories, isEmpty);
      expect((await store.read('addons'))?['lastChange'], isNull);
    });

    test('repositório corrompido é ignorado na carga', () async {
      final store = InMemoryLocalStore();
      await store.write('addon_repos', {
        'items': [
          {
            'id': 'r1',
            'name': 'Bom',
            'originUrl': 'https://exemplo.com/a.json',
            'trusted': false,
            'addedAt': DateTime(2026, 1, 1).toIso8601String(),
          },
          {'id': 'ruim'},
        ],
      });
      final service = LocalAddonService(store, platform: 'windows');
      await service.load();
      expect(service.repositories.map((r) => r.name), ['Bom']);
    });
  });
}
