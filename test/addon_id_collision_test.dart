import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_package.dart';
import 'package:player/services/local_addon_service.dart';
import 'support/demo_addons.dart';

AddonPackage packageOf(String id) => AddonPackage(
      manifest: AddonManifest.fromMap(demoManifestJson(id: id)),
      sha256: 'x',
      catalogJson: '{"items": []}',
    );

void main() {
  group('ids que viram a mesma pasta no Windows', () {
    late Directory dir;
    late LocalAddonService service;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('olympus_ids');
      service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        packageDir: dir,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('id que só difere em maiúsculas é recusado, nos dois caminhos',
        () async {
      await service.installPackage(packageOf('News.Cat'),
          originTrusted: true);

      await expectLater(
        service.installPackage(packageOf('news.cat'), originTrusted: true),
        throwsA(isA<AddonError>()),
      );
      await expectLater(
        service.install(
            AddonManifest.fromMap(demoManifestJson(id: 'NEWS.CAT')),
            originTrusted: true),
        throwsA(isA<AddonError>()),
      );
      expect(service.addons.map((a) => a.manifest.id), ['News.Cat']);
    });

    test('a pasta do primeiro fica intacta', () async {
      final first = await service.installPackage(packageOf('News.Cat'),
          originTrusted: true);
      final catalog = File('${first.packageDir}${Platform.pathSeparator}'
          'catalog.json');

      await service
          .installPackage(packageOf('news.cat'), originTrusted: true)
          .then<void>((_) {}, onError: (_) {});

      expect(catalog.existsSync(), isTrue);
    });
  });

  test('id com ponto no fim é inválido', () {
    for (final id in ['foo.', 'foo..']) {
      expect(() => AddonManifest.fromMap(demoManifestJson(id: id)),
          throwsA(isA<AddonError>()),
          reason: id);
    }
    for (final id in ['foo', 'a', 'a.b-c_d', 'A1']) {
      expect(AddonManifest.fromMap(demoManifestJson(id: id)).id, id);
    }
  });
}
