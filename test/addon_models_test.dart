import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';

Map<String, Object?> validManifest() => {
      'id': 'demo.catalogo',
      'name': 'Catálogo Demo',
      'version': '1.2.3',
      'author': 'Equipe Player',
      'description': 'Add-on fictício para testes.',
      'icon': 'movie',
      'homepage': 'https://exemplo.com/demo',
      'repository': 'demo-repo',
      'permissions': ['catalog.read', 'playback.open'],
      'supportedPlatforms': ['windows', 'linux'],
      'contentTypes': ['video'],
      'updateUrl': 'https://exemplo.com/demo/manifest.json',
      'legalNotice': 'Demonstração sem conteúdo real.',
    };

void expectInvalid(Map<String, Object?> map, String contains) {
  try {
    AddonManifest.fromMap(map);
    fail('manifesto inválido foi aceito');
  } on AddonError catch (error) {
    expect(error.code, 'addon.invalid-manifest');
    expect(error.message, contains_(contains));
  }
}

Matcher contains_(String value) => predicate<String>(
      (message) => message.contains(value),
      'contém "$value"',
    );

void main() {
  group('AddonManifest', () {
    test('manifesto válido passa e preserva os campos', () {
      final manifest = AddonManifest.fromMap(validManifest());
      expect(manifest.id, 'demo.catalogo');
      expect(manifest.version, '1.2.3');
      expect(manifest.permissions, ['catalog.read', 'playback.open']);
      expect(manifest.supports('windows'), isTrue);
      expect(manifest.supports('android'), isFalse);

      final roundTrip = AddonManifest.fromMap(manifest.toMap());
      expect(roundTrip.toMap(), manifest.toMap());
    });

    test('parseJson aceita manifesto válido em texto', () {
      final manifest =
          AddonManifest.parseJson(jsonEncode(validManifest()));
      expect(manifest.id, 'demo.catalogo');
      expect(manifest.version, '1.2.3');
    });

    test('parseJson rejeita JSON malformado sem vazar detalhe interno', () {
      try {
        AddonManifest.parseJson('{nao e json');
        fail('JSON malformado foi aceito');
      } on AddonError catch (error) {
        expect(error.code, 'addon.invalid-manifest');
        expect(error.message, contains_('JSON'));
      }
    });

    test('parseJson rejeita JSON que não é objeto', () {
      try {
        AddonManifest.parseJson('["um", "array"]');
        fail('array foi aceito como manifesto');
      } on AddonError catch (error) {
        expect(error.code, 'addon.invalid-manifest');
        expect(error.message, contains_('objeto'));
      }
    });

    test('parseJson rejeita texto acima do teto sem decodificar', () {
      final big = '{"id":"x",${' ' * (256 * 1024)}}';
      try {
        AddonManifest.parseJson(big);
        fail('manifesto gigante foi aceito');
      } on AddonError catch (error) {
        expect(error.code, 'addon.invalid-manifest');
        expect(error.message, contains_('grande demais'));
      }
    });

    test('parseJson delega as regras do fromMap', () {
      final map = Map<String, Object?>.of(validManifest())
        ..['version'] = 'bogus';
      try {
        AddonManifest.parseJson(jsonEncode(map));
        fail('versão inválida foi aceita');
      } on AddonError catch (error) {
        expect(error.code, 'addon.invalid-manifest');
        expect(error.message, contains_('Versão'));
      }
    });

    test('compareVersions ordena nucleo e sufixo', () {
      int cmp(String a, String b) => AddonManifest.compareVersions(a, b);
      expect(cmp('1.0.0', '1.0.0'), 0);
      expect(cmp('1.0.1', '1.0.0'), greaterThan(0));
      expect(cmp('1.0.0', '1.1.0'), lessThan(0));
      expect(cmp('2.0.0', '10.0.0'), lessThan(0));
      expect(cmp('1.0.0', '1.0.0-beta'), greaterThan(0));
      expect(cmp('1.0.0-alpha', '1.0.0-beta'), lessThan(0));
      expect(cmp('1.0.0-beta', '1.0.0-beta'), 0);
    });

    test('changelog e opcional com teto', () {
      final absent = Map<String, Object?>.of(validManifest())
        ..remove('changelog');
      expect(AddonManifest.fromMap(absent).changelog, isNull);

      final present = Map<String, Object?>.of(validManifest())
        ..['changelog'] = 'Novidades.';
      final manifest = AddonManifest.fromMap(present);
      expect(manifest.changelog, 'Novidades.');
      expect(
          AddonManifest.fromMap(manifest.toMap()).changelog, 'Novidades.');

      final big = Map<String, Object?>.of(validManifest())
        ..['changelog'] = 'x' * 8001;
      expectInvalid(big, 'changelog');
    });

    test('updateUrl ausente ou vazio é aceito', () {
      final absent = Map<String, Object?>.of(validManifest())
        ..remove('updateUrl');
      expect(AddonManifest.fromMap(absent).updateUrl, isNull);

      final empty = Map<String, Object?>.of(validManifest())
        ..['updateUrl'] = '  ';
      expect(AddonManifest.fromMap(empty).updateUrl, isNull);
    });

    test('sem permissões é válido (mais restritivo)', () {
      final map = Map<String, Object?>.of(validManifest())
        ..['permissions'] = <String>[];
      expect(AddonManifest.fromMap(map).permissions, isEmpty);
    });

    test('campos obrigatórios ausentes são rejeitados', () {
      for (final key in [
        'id',
        'name',
        'version',
        'author',
        'description',
        'icon',
        'homepage',
        'repository',
        'legalNotice',
      ]) {
        final map = Map<String, Object?>.of(validManifest())..remove(key);
        expectInvalid(map, '');
      }
      final blank = Map<String, Object?>.of(validManifest())
        ..['name'] = '   ';
      expectInvalid(blank, 'Nome');
    });

    test('id e versão seguem os formatos', () {
      final badId = Map<String, Object?>.of(validManifest())
        ..['id'] = 'tem espaço!';
      expectInvalid(badId, 'Identificador');

      for (final version in ['1.2', '1.2.3.4.5', 'abc', '1,2,3']) {
        final map = Map<String, Object?>.of(validManifest())
          ..['version'] = version;
        expectInvalid(map, 'Versão');
      }
      final prerelease = Map<String, Object?>.of(validManifest())
        ..['version'] = '1.2.3-beta.1';
      expect(AddonManifest.fromMap(prerelease).version, '1.2.3-beta.1');
    });

    test('permissão e plataforma desconhecidas são rejeitadas', () {
      final permission = Map<String, Object?>.of(validManifest())
        ..['permissions'] = ['catalog.read', 'root.access'];
      expectInvalid(permission, 'root.access');

      final platform = Map<String, Object?>.of(validManifest())
        ..['supportedPlatforms'] = ['windows', 'tizen'];
      expectInvalid(platform, 'tizen');

      final noPlatform = Map<String, Object?>.of(validManifest())
        ..['supportedPlatforms'] = <String>[];
      expectInvalid(noPlatform, 'plataforma');

      final noContent = Map<String, Object?>.of(validManifest())
        ..['contentTypes'] = <String>[];
      expectInvalid(noContent, 'conteúdo');
    });

    test('valores acima do teto são rejeitados', () {
      final longName = Map<String, Object?>.of(validManifest())
        ..['name'] = 'n' * 513;
      expectInvalid(longName, 'tamanho máximo');

      final manyPermissions = Map<String, Object?>.of(validManifest())
        ..['permissions'] = List.filled(65, 'catalog.read');
      expectInvalid(manyPermissions, 'tamanho máximo');

      final longUrl = Map<String, Object?>.of(validManifest())
        ..['updateUrl'] = 'https://exemplo.com/${'a' * 2048}';
      expectInvalid(longUrl, 'tamanho máximo');
    });

    test('updateUrl inválida é rejeitada', () {
      final bad = Map<String, Object?>.of(validManifest())
        ..['updateUrl'] = 'ftp://exemplo.com/m.json';
      expectInvalid(bad, 'atualização');

      final typed = Map<String, Object?>.of(validManifest())
        ..['updateUrl'] = 42;
      expectInvalid(typed, 'atualização');
    });
  });

  group('AddonInfo', () {
    AddonInfo info() => AddonInfo(
          manifest: AddonManifest.fromMap(validManifest()),
          installedAt: DateTime(2026, 5, 5),
        );

    test('padroes: inativo e origem nao confiavel', () {
      final current = info();
      expect(current.state, AddonState.inactive);
      expect(current.originTrusted, isFalse);
      expect(current.diagnostic, isNull);
    });

    test('copyWith troca estado e diagnostico', () {
      final failed = info().copyWith(
        state: AddonState.error,
        diagnostic: () => 'Catálogo indisponível.',
      );
      expect(failed.state, AddonState.error);
      expect(failed.diagnostic, 'Catálogo indisponível.');
      expect(failed.manifest.id, 'demo.catalogo');
    });

    test('toMap/fromMap preservam os campos', () {
      final current = info().copyWith(
        state: AddonState.active,
        originTrusted: true,
        updatedAt: () => DateTime(2026, 6, 6),
      );
      final roundTrip = AddonInfo.fromMap(current.toMap());
      expect(roundTrip.state, AddonState.active);
      expect(roundTrip.originTrusted, isTrue);
      expect(roundTrip.installedAt, DateTime(2026, 5, 5));
      expect(roundTrip.updatedAt, DateTime(2026, 6, 6));
      expect(roundTrip.manifest.version, '1.2.3');
    });

    test('updateAvailable e deferredVersion fazem round-trip', () {
      final current = info().copyWith(
        updateAvailable: true,
        deferredVersion: () => '2.0.0',
      );
      final roundTrip = AddonInfo.fromMap(current.toMap());
      expect(roundTrip.updateAvailable, isTrue);
      expect(roundTrip.deferredVersion, '2.0.0');
    });

    test('fromMap sem as chaves novas usa os padroes', () {
      final map = info().toMap()
        ..remove('updateAvailable')
        ..remove('deferredVersion');
      final roundTrip = AddonInfo.fromMap(map);
      expect(roundTrip.updateAvailable, isFalse);
      expect(roundTrip.deferredVersion, isNull);
    });
  });

  group('AddonRepository', () {
    test('toMap/fromMap preservam os campos', () {
      final repo = AddonRepository(
        id: 'demo-repo',
        name: 'Repositório Demo',
        originUrl: 'https://exemplo.com/repo.json',
        trusted: true,
        addedAt: DateTime(2026, 5, 5),
      );
      final roundTrip = AddonRepository.fromMap(repo.toMap());
      expect(roundTrip.id, 'demo-repo');
      expect(roundTrip.originUrl, 'https://exemplo.com/repo.json');
      expect(roundTrip.trusted, isTrue);
    });

    test('origem ausente ou invalida e rejeitada', () {
      for (final url in ['', '   ', 'ftp://x.com/r.json', 'nao e url']) {
        try {
          AddonRepository.fromMap({
            'id': 'r',
            'name': 'R',
            'originUrl': url,
            'addedAt': DateTime(2026, 5, 5).toIso8601String(),
          });
          fail('repositório inválido foi aceito: $url');
        } on AddonError catch (error) {
          expect(error.code, 'addon.invalid-manifest');
        }
      }
    });

    test('parseListing decodifica manifestos embutidos', () {
      final manifests = AddonRepository.parseListing(
        jsonEncode({
          'addons': [validManifest()],
        }),
      );
      expect(manifests.map((m) => m.id), ['demo.catalogo']);
    });

    test('parseListing aceita listagem vazia', () {
      expect(AddonRepository.parseListing('{"addons":[]}'), isEmpty);
    });

    test('parseListing reprova envelope malformado', () {
      for (final raw in ['{nao e json', '[]', '{}', '{"addons":{}}']) {
        try {
          AddonRepository.parseListing(raw);
          fail('listagem inválida foi aceita: $raw');
        } on AddonError catch (error) {
          expect(error.code, 'addon.invalid-manifest');
          expect(error.message, contains_('repositório'));
        }
      }
    });

    test('parseListing reprova item invalido com motivo especifico', () {
      final bad = Map<String, Object?>.of(validManifest())
        ..['version'] = 'bogus';
      try {
        AddonRepository.parseListing(
          jsonEncode({
            'addons': [bad],
          }),
        );
        fail('item inválido foi aceito');
      } on AddonError catch (error) {
        expect(error.code, 'addon.invalid-manifest');
        expect(error.message, contains_('Versão'));
      }
    });
  });
}
