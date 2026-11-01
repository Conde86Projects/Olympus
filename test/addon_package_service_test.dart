import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/addon_package.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/local_addon_service.dart';

/// T2: gerenciador de pacotes. Costuras da Parte 2: [LocalAddonService]
/// com [InMemoryLocalStore] e fetcher falso; disco em pasta temporária.
class _FakeFetcher extends AddonFetcher {
  const _FakeFetcher(this.bodies, {this.byteBodies = const {}});

  final Map<String, String> bodies;
  final Map<String, Uint8List> byteBodies;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }

  /// Entrega fatiada com progresso; completar [cancel] no meio
  /// interrompe com o motivo de cancelamento (contrato real).
  @override
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    var cancelled = false;
    cancel?.then((_) => cancelled = true);
    final bytes = byteBodies[url];
    if (bytes == null) {
      throw const AddonError.fetchFailed(
        'Não foi possível buscar o endereço. Verifique a conexão.',
      );
    }
    const slice = 64 * 1024;
    final out = <int>[];
    for (var i = 0; i < bytes.length; i += slice) {
      if (cancelled) {
        throw const AddonError.fetchFailed(fetchCancelledMessage);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (cancelled) {
        throw const AddonError.fetchFailed(fetchCancelledMessage);
      }
      final end = (i + slice).clamp(0, bytes.length);
      out.addAll(bytes.sublist(i, end));
      onProgress?.call(out.length, bytes.length);
    }
    return Uint8List.fromList(out);
  }
}

Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.addFile(ArchiveFile(name, content.length, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String feedJson([int count = 2]) => jsonEncode({
      'items': [
        for (var i = 1; i <= count; i++)
          {
            'id': 'v$i',
            'title': 'Vídeo $i',
            'sourceUrl': 'https://cdn.exemplo.com/v$i.mp4',
          },
      ],
    });

Uint8List packageZip({String? catalogUrl}) {
  final manifest = {
    ...demoManifestJson(),
    if (catalogUrl != null) 'catalogUrl': catalogUrl,
  };
  return zipOf({
    'addon.json': utf8.encode(jsonEncode(manifest)),
    if (catalogUrl == null) 'catalog.json': utf8.encode(feedJson()),
  });
}

class _Harness {
  _Harness(
      {Map<String, String> bodies = const {},
      Map<String, Uint8List> byteBodies = const {},
      bool allow = true})
      : _allow = allow,
        fetcher = _FakeFetcher(bodies, byteBodies: byteBodies);

  bool _allow;
  final _FakeFetcher fetcher;
  late final Directory packages;
  late final LocalAddonService addons;

  Future<void> open() async {
    packages =
        await Directory.systemTemp.createTemp('olympus-pacotes-');
    addons = LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: fetcher,
      packageDir: packages,
      allowUnknownSources: () => _allow,
    );
    addTearDown(() async {
      if (await packages.exists()) {
        await packages.delete(recursive: true);
      }
    });
  }

  set allow(bool value) => _allow = value;
}

void main() {
  group('instalação de pacote', () {
    test('prévia e instalação entram desativadas com origem e SHA', () async {
      final harness = _Harness();
      await harness.open();
      final bytes = packageZip();

      final preview = await harness.addons.previewPackage(bytes);
      final info = await harness.addons.installPackage(preview,
          originTrusted: false);

      expect(info.state, AddonState.inactive);
      expect(info.packageOrigin, AddonPackageOrigin.file);
      expect(info.packageSha256, sha256.convert(bytes).toString());
      expect(info.packageDir, isNotNull);
      final dir = Directory(info.packageDir!);
      expect(await dir.exists(), isTrue);
      expect(
          await File(
                  '${dir.path}${Platform.pathSeparator}catalog.json')
              .exists(),
          isTrue);
      expect(harness.addons.getStatus('demo.catalogo'),
          AddonState.inactive);
    });

    test('botão desligado recusa prévia e instalação', () async {
      final harness = _Harness(allow: false);
      await harness.open();
      await expectLater(
        () => harness.addons.previewPackage(packageZip()),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      final package = readAddonPackage(packageZip());
      await expectLater(
        () => harness.addons.installPackage(package, originTrusted: false),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      expect(harness.addons.addons, isEmpty);
      expect(await harness.packages.list().toList(), isEmpty);
    });

    test('zip inválido não deixa pasta nem registro', () async {
      final harness = _Harness();
      await harness.open();
      await expectLater(
        () => harness.addons.previewPackage(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AddonError>()),
      );
      expect(harness.addons.addons, isEmpty);
      expect(await harness.packages.list().toList(), isEmpty);
    });

    test('falha ao salvar não deixa pasta nem registro', () async {
      final harness = _Harness();
      await harness.open();
      final preview =
          await harness.addons.previewPackage(packageZip());
      final fileRoot = File(
          '${harness.packages.path}${Platform.pathSeparator}arquivo');
      await fileRoot.writeAsString('ocupa o lugar');
      final broken = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: harness.fetcher,
        packageDir: Directory(fileRoot.path),
      );
      await expectLater(
        () => broken.installPackage(preview, originTrusted: false),
        throwsA(isA<AddonError>()),
      );
      expect(broken.addons, isEmpty);
    });

    test('remover apaga a pasta e mantém o registro limpo', () async {
      final harness = _Harness();
      await harness.open();
      final preview =
          await harness.addons.previewPackage(packageZip());
      final info = await harness.addons.installPackage(preview,
          originTrusted: false);
      final dir = Directory(info.packageDir!);
      await harness.addons.uninstall('demo.catalogo');
      expect(await dir.exists(), isFalse);
      expect(await dir.parent.exists(), isFalse);
      expect(harness.addons.addons, isEmpty);
    });

    test('limpar dados apaga as pastas', () async {
      final harness = _Harness();
      await harness.open();
      final preview =
          await harness.addons.previewPackage(packageZip());
      await harness.addons.installPackage(preview, originTrusted: false);
      await harness.addons.clearAllData();
      expect(await harness.packages.exists(), isFalse);
      expect(harness.addons.addons, isEmpty);
      expect(harness.addons.repositories, isEmpty);
    });

    test('remoção não sai da raiz de pacotes', () async {
      final base = await Directory.systemTemp.createTemp('olympus-raiz-');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });
      final packages = Directory('${base.path}/pacotes');
      final evil =
          Directory('${base.path}/pacotes-evil/demo.catalogo/1.0.0');
      await evil.create(recursive: true);
      final sentinel = File('${evil.path}/sentinela.txt');
      await sentinel.writeAsString('intacto');
      final store = InMemoryLocalStore();
      await store.write(LocalAddonService.storeKey, {
        'items': [
          {
            'manifest': demoManifestJson(),
            'state': 'inactive',
            'originTrusted': true,
            'installedAt': DateTime(2026, 1, 1).toIso8601String(),
            'updateAvailable': false,
            'packageOrigin': 'file',
            'packageSha256': 'abc',
            'packageDir': evil.path,
          },
        ],
        'lastChange': null,
        'previous': {},
      });
      final service = LocalAddonService(
        store,
        platform: 'windows',
        fetcher: const _FakeFetcher({}),
        packageDir: packages,
      );
      await service.load();
      await service.uninstall('demo.catalogo');
      expect(await sentinel.exists(), isTrue);
      await service.clearAllData();
      expect(await sentinel.exists(), isTrue);
    });

    test('documento antigo carrega sem perda', () async {
      final store = InMemoryLocalStore();
      await store.write(LocalAddonService.storeKey, {
        'items': [
          {
            'manifest': demoManifestJson(),
            'state': 'inactive',
            'originTrusted': false,
            'installedAt':
                DateTime(2026, 1, 1).toIso8601String(),
            'updateAvailable': false,
          },
        ],
        'lastChange': null,
        'previous': {},
      });
      final service = LocalAddonService(
        store,
        platform: 'windows',
        fetcher: const _FakeFetcher({}),
      );
      await service.load();
      final info = service.findById('demo.catalogo')!;
      expect(info.packageOrigin, isNull);
      expect(info.packageSha256, isNull);
      expect(info.packageDir, isNull);
      expect(info.state, AddonState.inactive);
    });
  });

  group('catálogo embutido', () {
    test('abre e toca sem internet', () async {
      final harness = _Harness(bodies: const {});
      await harness.open();
      final preview =
          await harness.addons.previewPackage(packageZip());
      await harness.addons.installPackage(preview, originTrusted: false);
      await harness.addons.enable('demo.catalogo');

      final catalog = await harness.addons.getCatalog('demo.catalogo');

      expect(catalog.map((i) => i.title), ['Vídeo 1', 'Vídeo 2']);
    });

    test('catalogUrl tem prioridade; reserva em falha de rede', () async {
      const remoteUrl = 'https://f.exemplo.com/remoto.json';
      final remote = jsonEncode({
        'items': [
          {
            'id': 'r1',
            'title': 'Remoto Um',
            'sourceUrl': 'https://cdn.exemplo.com/r1.mp4',
          },
        ],
      });
      final harness = _Harness(bodies: {remoteUrl: remote});
      await harness.open();
      final preview = await harness.addons
          .previewPackage(packageZip(catalogUrl: remoteUrl));
      await harness.addons.installPackage(preview, originTrusted: false);
      await harness.addons.enable('demo.catalogo');

      final online =
          await harness.addons.getCatalog('demo.catalogo');
      expect(online.map((i) => i.title), ['Remoto Um']);
    });

    test('reserva embutida em falha de rede', () async {
      const remoteUrl = 'https://f.exemplo.com/remoto.json';
      final harness = _Harness(bodies: const {});
      await harness.open();
      final manifest = {
        ...demoManifestJson(),
        'catalogUrl': remoteUrl,
      };
      final both = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifest)),
        'catalog.json': utf8.encode(feedJson()),
      });
      final preview = await harness.addons.previewPackage(both);
      await harness.addons.installPackage(preview, originTrusted: false);
      await harness.addons.enable('demo.catalogo');

      final catalog =
          await harness.addons.getCatalog('demo.catalogo');

      expect(catalog.map((i) => i.title), ['Vídeo 1', 'Vídeo 2']);
      expect(harness.addons.getStatus('demo.catalogo'),
          AddonState.active);
    });
  });

  group('pacote por link (T3)', () {
    test('link baixa e chega à prévia com progresso', () async {
      const link = 'https://pacotes.exemplo.com/demo.zip';
      final bytes = packageZip();
      final harness = _Harness(byteBodies: {link: bytes});
      await harness.open();

      final seen = <String>[];
      final package = await harness.addons.previewPackageFromLink(
        link,
        onProgress: (received, total) =>
            seen.add('$received/$total'),
      );

      expect(package.manifest.id, 'demo.catalogo');
      expect(package.sha256, sha256.convert(bytes).toString());
      expect(package.catalogItemCount, 2);
      expect(seen, isNotEmpty);
      expect(seen.last, '${bytes.length}/${bytes.length}');
    });

    test('botão desligado recusa o link', () async {
      const link = 'https://pacotes.exemplo.com/demo.zip';
      final harness = _Harness(
        allow: false,
        byteBodies: {link: packageZip()},
      );
      await harness.open();

      await expectLater(
        () => harness.addons.previewPackageFromLink(link),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      expect(harness.addons.addons, isEmpty);
    });

    test('cancelar o download propaga o motivo sem temporário',
        () async {
      const link = 'https://pacotes.exemplo.com/grande.zip';
      final big = Uint8List.fromList(
        packageZip() + List<int>.filled(1024 * 1024, 0),
      );
      final harness = _Harness(byteBodies: {link: big});
      await harness.open();

      final cancel = Completer<void>();
      try {
        await harness.addons.previewPackageFromLink(
          link,
          onProgress: (received, total) {
            if (!cancel.isCompleted) cancel.complete();
          },
          cancel: cancel.future,
        );
        fail('deveria ter cancelado');
      } on AddonError catch (error) {
        expect(error.message, fetchCancelledMessage);
      }
      expect(await harness.packages.list().isEmpty, isTrue);
      expect(harness.addons.addons, isEmpty);
    });
  });
}
