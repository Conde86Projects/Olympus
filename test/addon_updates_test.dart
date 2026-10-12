import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/startup_guard.dart';

class _FakeFetcher extends AddonFetcher {
  _FakeFetcher(this.bodies);

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

class _Harness {
  _Harness({
    Map<String, String>? bodies,
    String platform = 'windows',
    Set<String> faultyIds = const {},
  })  : store = InMemoryLocalStore(),
        bodies = bodies ?? {} {
    addons = LocalAddonService(
      store,
      platform: platform,
      faultyIds: faultyIds,
      fetcher: _FakeFetcher(this.bodies),
    );
  }

  final InMemoryLocalStore store;
  final Map<String, String> bodies;
  late final LocalAddonService addons;

  static const updateUrl = 'https://exemplo.com/demo/manifest.json';

  Future<void> install({
    String id = 'demo.catalogo',
    String version = '1.0.0',
    String? url = updateUrl,
    List<String>? platforms,
  }) async {
    final json = demoManifestJson(id: id, version: version);
    if (url != null) json['updateUrl'] = url;
    if (platforms != null) json['supportedPlatforms'] = platforms;
    await addons.install(
      AddonManifest.fromMap(json),
      originTrusted: false,
    );
  }

  /// Serve `version` no updateUrl padrao, com changelog.
  void serve({String version = '1.1.0', List<String>? platforms}) {
    final json = demoManifestJson(version: version);
    json['updateUrl'] = updateUrl;
    json['changelog'] = 'Novidades da $version.';
    if (platforms != null) json['supportedPlatforms'] = platforms;
    bodies[updateUrl] = jsonEncode(json);
  }
}

void main() {
  group('updates no service', () {
    test('check marca a flag e devolve o manifesto mais novo', () async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');

      final found = await harness.addons.checkForUpdates();

      expect(found.map((m) => m.version), ['1.1.0']);
      expect(found.single.changelog, 'Novidades da 1.1.0.');
      expect(
          harness.addons.findById('demo.catalogo')!.updateAvailable,
          isTrue);
      // Flag persiste entre cargas.
      final fresh = LocalAddonService(harness.store, platform: 'windows');
      await fresh.load();
      expect(fresh.findById('demo.catalogo')!.updateAvailable, isTrue);
    });

    test('check pula sem-url, mesma versao e anterior', () async {
      final harness = _Harness();
      await harness.install(id: 'a.semurl', url: null);
      await harness.install(id: 'b.igual', version: '1.1.0');
      await harness.install(id: 'c.novo', version: '2.0.0');
      harness.serve(version: '1.1.0');

      final found = await harness.addons.checkForUpdates();

      expect(found, isEmpty);
      for (final id in ['a.semurl', 'b.igual', 'c.novo']) {
        expect(harness.addons.findById(id)!.updateAvailable, isFalse);
      }
    });

    test('check pula falha de rede, id trocado e manifesto ruim', () async {
      final harness = _Harness();
      await harness.install(id: 'a.off');
      await harness.install(id: 'b.outro');
      await harness.install(id: 'c.ruim');
      // updateUrl padrao serve manifesto de OUTRO id para todos: alem
      // de id trocado, vale como "nada valido encontrado".
      final json = demoManifestJson(id: 'outro.id', version: '9.9.9');
      harness.bodies[_Harness.updateUrl] = jsonEncode(json);

      final found = await harness.addons.checkForUpdates();

      expect(found, isEmpty);
      expect(harness.addons.findById('a.off')!.updateAvailable, isFalse);
    });

    test('check limpa flag obsoleta', () async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      expect(await harness.addons.checkForUpdates(), hasLength(1));

      harness.serve(version: '1.0.0');
      expect(await harness.addons.checkForUpdates(), isEmpty);
      expect(
          harness.addons.findById('demo.catalogo')!.updateAvailable,
          isFalse);
    });

    test('update aplica e guarda a anterior', () async {
      final harness = _Harness();
      await harness.install();
      await harness.addons.enable('demo.catalogo');
      harness.serve(version: '1.1.0');

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.manifest.version, '1.1.0');
      expect(updated.state, AddonState.active);
      expect(updated.updatedAt, isNotNull);
      expect(updated.updateAvailable, isFalse);
      expect(harness.addons.previousVersion('demo.catalogo'), '1.0.0');
      // Update conta como alteracao para o modo seguro.
      final change =
          await StartupGuard(harness.store).readLastChange();
      expect(change!.id, 'demo.catalogo');
    });

    test('update bloqueia incompativel com motivo', () async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0', platforms: ['android']);

      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.incompatible')),
      );
      expect(harness.addons.findById('demo.catalogo')!.manifest.version,
          '1.0.0');
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
    });

    test('update rejeita id trocado e sem novidade', () async {
      final harness = _Harness();
      await harness.install();
      final other = demoManifestJson(id: 'outro.id', version: '9.9.9');
      harness.bodies[_Harness.updateUrl] = jsonEncode(other);
      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );

      harness.serve(version: '1.0.0');
      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.no-update')),
      );
    });

    test('update propaga falha de rede', () async {
      final harness = _Harness();
      await harness.install();
      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.fetch-failed')),
      );
    });

    test('defer esconde a versao ate surgir outra mais nova', () async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      expect(await harness.addons.checkForUpdates(), hasLength(1));

      await harness.addons.deferUpdate('demo.catalogo');
      expect(await harness.addons.checkForUpdates(), isEmpty);
      expect(
          harness.addons.findById('demo.catalogo')!.updateAvailable,
          isFalse);

      harness.serve(version: '1.2.0');
      final found = await harness.addons.checkForUpdates();
      expect(found.map((m) => m.version), ['1.2.0']);
    });

    test('rollback restaura manifesto e estado', () async {
      final harness = _Harness();
      await harness.install();
      await harness.addons.enable('demo.catalogo');
      harness.serve(version: '1.1.0');
      await harness.addons.update('demo.catalogo');

      final restored = await harness.addons.rollback('demo.catalogo');

      expect(restored.manifest.version, '1.0.0');
      expect(restored.state, AddonState.active);
      expect(restored.updateAvailable, isTrue);
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);

      await expectLater(
        () => harness.addons.rollback('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.no-backup')),
      );

      final fresh = LocalAddonService(harness.store, platform: 'windows');
      await fresh.load();
      expect(fresh.findById('demo.catalogo')!.manifest.version, '1.0.0');
    });

    test('rollback sem backup falha com motivo', () async {
      final harness = _Harness();
      await harness.install();
      await expectLater(
        () => harness.addons.rollback('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.no-backup')),
      );
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
      expect(harness.addons.previousVersion('desconhecido'), isNull);
    });

    test('desinstalar descarta o backup', () async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.addons.update('demo.catalogo');
      expect(harness.addons.previousVersion('demo.catalogo'), '1.0.0');

      await harness.addons.uninstall('demo.catalogo');
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
    });

    test('update em erro limpa o diagnostico e desativa', () async {
      final harness = _Harness(faultyIds: const {'demo.catalogo'});
      await harness.install();
      await harness.addons.enable('demo.catalogo');
      await harness.addons.getCatalog('demo.catalogo');
      expect(harness.addons.findById('demo.catalogo')!.state,
          AddonState.error);
      harness.serve(version: '1.1.0');

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.state, AddonState.inactive);
      expect(updated.diagnostic, isNull);
      expect(updated.manifest.version, '1.1.0');
    });
  });
}
