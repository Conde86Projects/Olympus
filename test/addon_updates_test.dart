import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/services/addon_fetcher.dart';
import 'support/demo_addons.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/startup_guard.dart';

class _FakeFetcher extends AddonFetcher {
  _FakeFetcher(this.bodies, {this.byteBodies = const {}});

  final Map<String, String> bodies;
  final Map<String, Uint8List> byteBodies;

  @override
  Future<String> fetchText(String url, {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }

  @override
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    final bytes = byteBodies[url];
    if (bytes == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return bytes;
  }
}

class _Harness {
  _Harness({
    Map<String, String>? bodies,
    Map<String, Uint8List>? byteBodies,
    String platform = 'windows',
    Set<String> faultyIds = const {},
    Directory? packages,
  })  : store = InMemoryLocalStore(),
        bodies = bodies ?? {},
        byteBodies = byteBodies ?? {} {
    addons = LocalAddonService(
      store,
      platform: platform,
      catalogWithoutFeed: catalogFailingFor(faultyIds),
      fetcher: _FakeFetcher(this.bodies, byteBodies: this.byteBodies),
      packageDir: packages,
    );
  }

  final InMemoryLocalStore store;
  final Map<String, String> bodies;
  final Map<String, Uint8List> byteBodies;
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
  group('update que muda a origem do catálogo', () {
    const feedA = 'https://a.exemplo.org/feed.json';
    const feedB = 'https://b.exemplo.org/feed.json';

    Future<_Harness> activeOn(String feed) async {
      final harness = _Harness();
      await harness.addons.install(
        AddonManifest.fromMap({
          ...demoManifestJson(),
          'updateUrl': _Harness.updateUrl,
          'catalogUrl': feed,
        }),
        originTrusted: true,
      );
      await harness.addons.enable('demo.catalogo');
      return harness;
    }

    void serve(_Harness harness, String? feed) {
      harness.bodies[_Harness.updateUrl] = jsonEncode({
        ...demoManifestJson(version: '1.1.0'),
        'updateUrl': _Harness.updateUrl,
        if (feed != null) 'catalogUrl': feed,
      });
    }

    test('host novo desativa, sem buscar nele antes de aprovar', () async {
      final harness = await activeOn(feedA);
      serve(harness, feedB);
      harness.bodies[feedB] = jsonEncode({'items': []});

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.state, AddonState.inactive);
      expect(updated.diagnostic, LocalAddonService.approvalDiagnostic);
      expect(updated.needsApproval, isTrue);

      await harness.addons.enable('demo.catalogo');
      expect(harness.addons.getStatus('demo.catalogo'), AddonState.inactive);

      await harness.addons.approveSource('demo.catalogo');
      await harness.addons.enable('demo.catalogo');
      expect(harness.addons.getStatus('demo.catalogo'), AddonState.active);
    });

    test('mesmo host segue ativo', () async {
      final harness = await activeOn(feedA);
      serve(harness, 'https://a.exemplo.org/outro.json');

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.state, AddonState.active);
      expect(updated.diagnostic, isNull);
    });

    test('versão sem feed não fica presa pedindo aprovação', () async {
      final harness = await activeOn(feedA);
      serve(harness, null);

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.state, AddonState.active);
      expect(updated.needsApproval, isFalse);
    });
  });

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

  group('pacote de repositório (T5)', () {
    const repoOrigin = 'https://exemplo.com/repo.json';
    const packageUrl = 'https://exemplo.com/demo.zip';

    // Carimbo fixo: o ArchiveFile usa a hora atual por padrão e dois
    // zips gerados em segundos distintos teriam SHA distinto (flake).
    const zippedAt = 1767225600; // 2026-01-01 UTC.
    Uint8List packageZipBytes(
        {String version = '1.0.0', Map<String, Object?>? extra}) {
      final archive = Archive();
      final manifest = utf8.encode(jsonEncode({
        ...demoManifestJson(version: version),
        if (extra != null) ...extra,
      }));
      archive.addFile(ArchiveFile('addon.json', manifest.length, manifest)
        ..lastModTime = zippedAt);
      final catalog = utf8.encode(jsonEncode({
        'items': [
          {
            'id': 'v1',
            'title': 'Vídeo 1 ($version)',
            'sourceUrl': 'https://cdn.exemplo.com/v1.mp4',
          },
        ],
      }));
      archive.addFile(ArchiveFile('catalog.json', catalog.length, catalog)
        ..lastModTime = zippedAt);
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    String packageListing({
      required String version,
      required String sha,
      List<String>? platforms,
      String? catalogUrl,
    }) {
      return jsonEncode({
        'addons': [
          {
            ...demoManifestJson(version: version),
            if (platforms != null) 'supportedPlatforms': platforms,
            if (catalogUrl != null) 'catalogUrl': catalogUrl,
            'packageUrl': packageUrl,
            'sha256': sha,
          },
        ],
      });
    }

    Future<Directory> tempPackages() async {
      final dir = await Directory.systemTemp.createTemp('olympus-pacotes-t5-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      return dir;
    }

    Future<AddonRepository> installPackage(
      _Harness harness, {
      String version = '1.0.0',
      List<String>? platforms,
      String? sourceRepoId = 'auto',
    }) async {
      final zip = packageZipBytes(version: version);
      final sha = sha256.convert(zip).toString();
      final repo = await harness.addons.addRepository(
        name: 'Comunidade',
        originUrl: repoOrigin,
        trusted: true,
      );
      harness.bodies[repoOrigin] = packageListing(
        version: version,
        sha: sha,
        platforms: platforms,
      );
      harness.byteBodies[packageUrl] = zip;
      final manifest = AddonManifest.fromMap({
        ...demoManifestJson(version: version),
        if (platforms != null) 'supportedPlatforms': platforms,
        'packageUrl': packageUrl,
        'sha256': sha,
      });
      await harness.addons.installPackageFromRepo(
        manifest,
        originTrusted: true,
        sourceRepoId: sourceRepoId == 'auto' ? repo.id : sourceRepoId,
      );
      return repo;
    }

    Future<void> serveVersion(_Harness harness, String version,
        {List<String>? platforms, Uint8List? bytesOverride}) async {
      final zip = packageZipBytes(version: version);
      harness.bodies[repoOrigin] = packageListing(
        version: version,
        sha: sha256.convert(zip).toString(),
        platforms: platforms,
      );
      harness.byteBodies[packageUrl] = bytesOverride ?? zip;
    }

    String versionDir(Directory packages, String version) =>
        '${packages.path}${Platform.pathSeparator}demo.catalogo'
        '${Platform.pathSeparator}$version';

    test('check encontra versão nova no repositório de origem', () async {
      final harness = _Harness(packages: await tempPackages());
      await installPackage(harness);
      await serveVersion(harness, '2.0.0');

      final found = await harness.addons.checkForUpdates();

      expect(found.map((m) => m.version), ['2.0.0']);
      expect(found.single.packageUrl, packageUrl);
      expect(
          harness.addons.findById('demo.catalogo')!.updateAvailable,
          isTrue);
    });

    test('check ignora repositório removido', () async {
      final harness = _Harness(packages: await tempPackages());
      final repo = await installPackage(harness);
      await harness.addons.removeRepository(repo.id);
      await serveVersion(harness, '2.0.0');

      expect(await harness.addons.checkForUpdates(), isEmpty);
      expect(
          harness.addons.findById('demo.catalogo')!.updateAvailable,
          isFalse);
    });

    test('pacote novo em outro host desativa e pede aprovação', () async {
      final harness = _Harness(packages: await tempPackages());
      await installPackage(harness);
      await harness.addons.enable('demo.catalogo');
      final zip = packageZipBytes(version: '2.0.0');
      harness.bodies[repoOrigin] = packageListing(
        version: '2.0.0',
        sha: sha256.convert(zip).toString(),
        catalogUrl: 'https://outro.exemplo.org/feed.json',
      );
      harness.byteBodies[packageUrl] = zip;

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.state, AddonState.inactive);
      expect(updated.diagnostic, LocalAddonService.approvalDiagnostic);
    });

    test('update aplica pacote guardando a anterior', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      final repo = await installPackage(harness);
      await serveVersion(harness, '2.0.0');

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.manifest.version, '2.0.0');
      expect(updated.packageOrigin, AddonPackageOrigin.repository);
      expect(updated.packageSha256,
          sha256.convert(packageZipBytes(version: '2.0.0')).toString());
      expect(updated.packageDir, versionDir(packages, '2.0.0'));
      expect(await Directory(versionDir(packages, '2.0.0')).exists(), isTrue);
      expect(await Directory(versionDir(packages, '1.0.0')).exists(), isTrue);
      expect(updated.updateAvailable, isFalse);
      expect(harness.addons.previousVersion('demo.catalogo'), '1.0.0');
      expect(updated.sourceRepoId, repo.id);
    });

    test('terceira atualização apaga a mais antiga', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      await installPackage(harness);
      await serveVersion(harness, '2.0.0');
      await harness.addons.update('demo.catalogo');
      await serveVersion(harness, '3.0.0');
      await harness.addons.update('demo.catalogo');

      expect(await Directory(versionDir(packages, '3.0.0')).exists(), isTrue);
      expect(await Directory(versionDir(packages, '2.0.0')).exists(), isTrue);
      expect(await Directory(versionDir(packages, '1.0.0')).exists(), isFalse);
      expect(harness.addons.previousVersion('demo.catalogo'), '2.0.0');
      expect(harness.addons.findById('demo.catalogo')!.manifest.version,
          '3.0.0');
    });

    test('rollback restaura manifesto e catálogo juntos', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      await installPackage(harness);
      await serveVersion(harness, '2.0.0');
      await harness.addons.update('demo.catalogo');

      final restored = await harness.addons.rollback('demo.catalogo');

      expect(restored.manifest.version, '1.0.0');
      expect(restored.packageDir, versionDir(packages, '1.0.0'));
      expect(await Directory(versionDir(packages, '1.0.0')).exists(), isTrue);
      expect(await Directory(versionDir(packages, '2.0.0')).exists(), isFalse);
      final catalog = await File(
        '${versionDir(packages, '1.0.0')}${Platform.pathSeparator}catalog.json',
      ).readAsString();
      expect(catalog, contains('Vídeo 1 (1.0.0)'));
      expect(restored.updateAvailable, isTrue);
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
    });

    test('falha na atualização mantém a versão atual', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      await installPackage(harness);
      final good = packageZipBytes(version: '2.0.0');
      final tampered = Uint8List.fromList(good)..[10] = 0xFF ^ good[10];
      await serveVersion(harness, '2.0.0', bytesOverride: tampered);
      expect(await harness.addons.checkForUpdates(), hasLength(1));

      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>()
            .having((e) => e.code, 'code', 'addon.invalid-manifest')
            .having((e) => e.message, 'message', contains('Checksum'))),
      );

      final current = harness.addons.findById('demo.catalogo')!;
      expect(current.manifest.version, '1.0.0');
      expect(current.packageDir, versionDir(packages, '1.0.0'));
      expect(await Directory(versionDir(packages, '1.0.0')).exists(), isTrue);
      expect(await Directory(versionDir(packages, '2.0.0')).exists(), isFalse);
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
      expect(current.updateAvailable, isTrue);
    });

    test('versão adiada não reaparece no repositório', () async {
      final harness = _Harness(packages: await tempPackages());
      await installPackage(harness);
      await serveVersion(harness, '2.0.0');
      expect(await harness.addons.checkForUpdates(), hasLength(1));

      await harness.addons.deferUpdate('demo.catalogo');
      expect(await harness.addons.checkForUpdates(), isEmpty);

      await serveVersion(harness, '3.0.0');
      final found = await harness.addons.checkForUpdates();
      expect(found.map((m) => m.version), ['3.0.0']);
    });

    test('versão incompatível recusa na aplicação', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      await installPackage(harness);
      await serveVersion(harness, '2.0.0', platforms: ['android']);

      expect(await harness.addons.checkForUpdates(), hasLength(1));
      await expectLater(
        () => harness.addons.update('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.incompatible')),
      );
      expect(harness.addons.findById('demo.catalogo')!.manifest.version,
          '1.0.0');
      expect(harness.addons.previousVersion('demo.catalogo'), isNull);
      expect(await Directory(versionDir(packages, '2.0.0')).exists(), isFalse);
    });

    test('rollback de pacote sem backup falha com motivo', () async {
      final harness = _Harness(packages: await tempPackages());
      await installPackage(harness);
      await expectLater(
        () => harness.addons.rollback('demo.catalogo'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.no-backup')),
      );
    });

    test('sem repositório de origem usa o updateUrl', () async {
      final packages = await tempPackages();
      final harness = _Harness(packages: packages);
      const updateUrl = 'https://exemplo.com/demo/manifest.json';
      final zip = packageZipBytes(extra: {'updateUrl': updateUrl});
      final sha = sha256.convert(zip).toString();
      harness.byteBodies[packageUrl] = zip;
      final manifest = AddonManifest.fromMap({
        ...demoManifestJson(),
        'updateUrl': updateUrl,
        'packageUrl': packageUrl,
        'sha256': sha,
      });
      await harness.addons.installPackageFromRepo(
        manifest,
        originTrusted: true,
      );
      final next = demoManifestJson(version: '1.1.0');
      next['updateUrl'] = 'https://exemplo.com/demo/manifest.json';
      harness.bodies['https://exemplo.com/demo/manifest.json'] =
          jsonEncode(next);

      final updated = await harness.addons.update('demo.catalogo');

      expect(updated.manifest.version, '1.1.0');
      expect(updated.packageDir, versionDir(packages, '1.0.0'));
    });
  });
}
