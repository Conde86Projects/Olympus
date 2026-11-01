import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/services/addon_package.dart';
import 'package:player/services/demo_addons.dart';

/// T2: módulo de pacote `readAddonPackage`. Zips criados na hora, em
/// memória; valores esperados literais, nunca recalculados como o código.
Uint8List zipOf(Map<String, List<int>> entries, {Map<String, int>? modes}) {
  final archive = Archive();
  entries.forEach((name, content) {
    final file = ArchiveFile(name, content.length, content);
    final mode = modes?[name];
    if (mode != null) file.mode = mode;
    archive.addFile(file);
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, Object?> manifestJson({String? catalogUrl}) => {
      ...demoManifestJson(),
      if (catalogUrl != null) 'catalogUrl': catalogUrl,
    };

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

/// Troca o nome de uma entrada direto nos bytes (mesmo tamanho): o
/// codificador normaliza alguns nomes, então a invasão é crua.
Uint8List renameEntry(Uint8List zip, String from, String to) {
  assert(from.length == to.length);
  final fromBytes = utf8.encode(from);
  final toBytes = utf8.encode(to);
  final out = Uint8List.fromList(zip);
  for (var i = 0; i + fromBytes.length <= out.length; i++) {
    var hit = true;
    for (var j = 0; j < fromBytes.length; j++) {
      if (out[i + j] != fromBytes[j]) {
        hit = false;
        break;
      }
    }
    if (hit) out.setRange(i, i + toBytes.length, toBytes);
  }
  return out;
}

/// Liga o bit de criptografia nos cabeçalhos locais (bit 0 do flags).
Uint8List encryptZip(Uint8List zip) {
  final out = Uint8List.fromList(zip);
  for (var i = 0; i + 10 < out.length; i++) {
    if (out[i] == 0x50 &&
        out[i + 1] == 0x4B &&
        out[i + 2] == 0x03 &&
        out[i + 3] == 0x04) {
      out[i + 8] = out[i + 8] | 0x01;
    }
  }
  return out;
}

void expectRefused(Uint8List zip, String code, [String? message]) {
  try {
    readAddonPackage(zip);
  } on AddonError catch (error) {
    expect(error.code, code);
    if (message != null) expect(error.message, message);
    return;
  }
  fail('era para recusar o pacote');
}

void main() {
  group('pacote válido', () {
    test('raiz plana com catálogo embutido', () {
      final manifest = jsonEncode(manifestJson());
      final catalog = feedJson();
      final zip = zipOf({
        'addon.json': utf8.encode(manifest),
        'catalog.json': utf8.encode(catalog),
      });

      final package = readAddonPackage(zip);

      expect(package.manifest.id, 'demo.catalogo');
      expect(package.sha256, sha256.convert(zip).toString());
      expect(package.catalogJson, catalog);
      expect(package.catalogItemCount, 2);
      expect(package.catalogSample, ['Vídeo 1', 'Vídeo 2']);
      expect(package.icon, isNull);
      expect(package.fanart, isNull);
    });

    test('pasta única com tudo dentro', () {
      final manifest = jsonEncode(manifestJson());
      final catalog = feedJson();
      final zip = zipOf({
        'pacote/addon.json': utf8.encode(manifest),
        'pacote/catalog.json': utf8.encode(catalog),
      });

      final package = readAddonPackage(zip);

      expect(package.manifest.id, 'demo.catalogo');
      expect(package.catalogItemCount, 2);
    });

    test('só com catalogUrl, sem catalog.json', () {
      final manifest =
          jsonEncode(manifestJson(catalogUrl: 'https://f.exemplo.com/c.json'));
      final zip = zipOf({'addon.json': utf8.encode(manifest)});

      final package = readAddonPackage(zip);

      expect(package.manifest.catalogUrl, 'https://f.exemplo.com/c.json');
      expect(package.catalogJson, isNull);
      expect(package.catalogItemCount, isNull);
      expect(package.catalogSample, isEmpty);
    });

    test('amostra corta em 5 títulos', () {
      final catalog = feedJson(7);
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(catalog),
      });

      final package = readAddonPackage(zip);

      expect(package.catalogItemCount, 7);
      expect(package.catalogSample, [
        'Vídeo 1',
        'Vídeo 2',
        'Vídeo 3',
        'Vídeo 4',
        'Vídeo 5',
      ]);
    });

    test('ícone e fanart com assinatura válida passam', () {
      final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01];
      final jpg = [0xFF, 0xD8, 0xFF, 0xE0, 0x01];
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'icon.png': png,
        'fanart.jpg': jpg,
      });

      final package = readAddonPackage(zip);

      expect(package.icon, png);
      expect(package.fanart, jpg);
    });
  });

  group('recusa de formato', () {
    test('sem manifesto', () {
      final zip = zipOf({'catalog.json': utf8.encode(feedJson())});
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote não tem addon.json.');
    });

    test('manifesto inválido', () {
      final zip = zipOf({
        'addon.json': utf8.encode('{"id": "x"'),
        'catalog.json': utf8.encode(feedJson()),
      });
      expectRefused(zip, 'addon.invalid-manifest');
    });

    test('zip corrompido', () {
      final good = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
      });
      final bad = Uint8List.fromList(good.sublist(0, good.length ~/ 2));
      expectRefused(bad, 'addon.invalid-manifest',
          'O pacote está corrompido ou não é um zip válido.');
    });

    test('arquivo extra recusa o pacote', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'leia-me.txt': utf8.encode('oi'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem um arquivo não aceito: "leia-me.txt".');
    });

    test('código solto recusa o pacote', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'extra.py': utf8.encode('print(1)'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem um arquivo não aceito: "extra.py".');
    });

    test('addon do Kodi mostra a mensagem própria', () {
      final zip = zipOf({
        'addon.xml': utf8.encode('<addon id="x.y" version="1.0.0"></addon>'),
        'catalog.json': utf8.encode(feedJson()),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'Este é um add-on do Kodi. Ele traz código que o Olympus não executa, por isso não pode ser instalado.');
    });

    test('caminho com .. recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        '../fora.json': utf8.encode('{}'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem um caminho inválido: "../fora.json".');
    });

    test('caminho absoluto recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        '/absoluto.json': utf8.encode('{}'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem um caminho inválido: "/absoluto.json".');
    });

    test('barra invertida recusa', () {
      final zip = renameEntry(
        zipOf({
          'addon.json': utf8.encode(jsonEncode(manifestJson())),
          'catalog.json': utf8.encode(feedJson()),
        }),
        'catalog.json',
        r'pasta\x.json',
      );
      expectRefused(zip, 'addon.invalid-manifest',
          r'O pacote tem um caminho inválido: "pasta\x.json".');
    });

    test('zip dentro de zip recusa', () {
      final inner = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
      });
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'dentro.zip': inner,
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem zip dentro de zip, que o Olympus não abre.');
    });

    test('link simbólico recusa', () {
      final zip = zipOf(
        {
          'addon.json': utf8.encode(jsonEncode(manifestJson())),
          'catalog.json': utf8.encode(feedJson()),
          'atalho': [1, 2, 3],
        },
        modes: {'atalho': 41453},
      );
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem link simbólico, que o Olympus não abre.');
    });

    test('entrada criptografada recusa', () {
      final zip = encryptZip(zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
      }));
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem entrada criptografada, que o Olympus não abre.');
    });

    test('sem catálogo nenhum é recusado', () {
      final zip =
          zipOf({'addon.json': utf8.encode(jsonEncode(manifestJson()))});
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote precisa trazer catalog.json ou catalogUrl no manifesto.');
    });

    test('mistura raiz com pasta recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'pacote/catalog.json': utf8.encode(feedJson()),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote mistura arquivos da raiz com pasta.');
    });

    test('nome forjado em duplicata continua recusado', () {
      // O decodificador colapsa nomes iguais; o que sobra cai na
      // lista fechada. A recusa é o que importa, não a mensagem.
      final zip = renameEntry(
        zipOf({
          'pacote/aa.json': utf8.encode(jsonEncode(manifestJson())),
          'pacote/bb.json': utf8.encode(jsonEncode(manifestJson())),
          'pacote/catalog.json': utf8.encode(feedJson()),
        }),
        'pacote/aa.json',
        'pacote/bb.json',
      );
      expectRefused(zip, 'addon.invalid-manifest');
    });

    test('catálogo vazio recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(jsonEncode({'items': []})),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O catálogo do pacote está vazio.');
    });

    test('catálogo só com inválidos recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(jsonEncode({
          'items': [
            {'nada': 'aqui'}
          ]
        })),
      });
      expectRefused(zip, 'addon.invalid-manifest');
    });
  });

  group('índice de nomes', () {
    List<ArchiveFile> files(List<String> names) =>
        [for (final n in names) ArchiveFile(n, 1, [0])];

    test('duplicado recusa', () {
      expect(
        () => indexPackageFiles(
            files(['addon.json', 'addon.json', 'catalog.json']),
            ['addon.json', 'addon.json', 'catalog.json']),
        throwsA(isA<AddonError>()
            .having((e) => e.code, 'code', 'addon.invalid-manifest')
            .having((e) => e.message, 'message',
                'O pacote tem o arquivo duplicado: "addon.json".')),
      );
    });

    test('fechado e com manifesto indexa', () {
      final indexed = indexPackageFiles(
          files(['addon.json', 'catalog.json']),
          ['addon.json', 'catalog.json']);
      expect(indexed.keys, {'addon.json', 'catalog.json'});
    });
  });

  group('limites do pacote', () {
    test('compactado acima de 10 MB recusa', () {
      final zip = Uint8List(10 * 1024 * 1024 + 1);
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote é grande demais (limite de 10 MB).');
    });

    test('descompactado acima de 30 MB recusa', () {
      final big = List<int>.filled(31 * 1024 * 1024, 0);
      final zip = zipOf({'catalog.json': big});
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote passa do limite descompactado (30 MB).');
    });

    test('soma usa bytes reais, não o tamanho declarado', () {
      final files = [
        ArchiveFile('a', 1, [1, 2, 3, 4, 5]),
        ArchiveFile('b', 999, [6, 7]),
      ];
      expect(extractedBytesTotal(files), 7);
    });


    test('acima de 16 entradas recusa', () {
      final zip = zipOf({
        for (var i = 0; i < 17; i++) 'f$i.txt': utf8.encode('x'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O pacote tem entradas demais (limite de 16).');
    });

    test('addon.json acima de 256 KB recusa', () {
      final manifest =
          jsonEncode(manifestJson()).padRight(257 * 1024, ' ');
      final zip = zipOf({
        'addon.json': utf8.encode(manifest),
        'catalog.json': utf8.encode(feedJson()),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O manifesto é grande demais (limite de 256 KB).');
    });

    test('catalog.json acima de 256 KB recusa', () {
      final catalog = feedJson().padRight(257 * 1024, ' ');
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(catalog),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O catálogo é grande demais (limite de 256 KB).');
    });

    test('ícone acima de 1 MB recusa', () {
      final icon = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] +
          List<int>.filled(1024 * 1024, 0);
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'icon.png': icon,
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O ícone é grande demais (limite de 1 MB).');
    });

    test('ícone sem assinatura recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'icon.png': utf8.encode('sou texto, não imagem'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'O ícone não é um PNG nem um JPEG válido.');
    });

    test('fanart acima de 5 MB recusa', () {
      final fanart = [0xFF, 0xD8, 0xFF] + List<int>.filled(5 * 1024 * 1024, 0);
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'fanart.jpg': fanart,
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'A fanart é grande demais (limite de 5 MB).');
    });

    test('fanart sem assinatura recusa', () {
      final zip = zipOf({
        'addon.json': utf8.encode(jsonEncode(manifestJson())),
        'catalog.json': utf8.encode(feedJson()),
        'fanart.jpg': utf8.encode('sou texto, não imagem'),
      });
      expectRefused(zip, 'addon.invalid-manifest',
          'A fanart não é um PNG nem um JPEG válido.');
    });
  });
}
