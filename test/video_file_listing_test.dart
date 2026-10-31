import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/video_file_listing.dart';

void main() {
  group('isVideoFileName', () {
    test('aceita vídeos sem diferenciar maiúsculas', () {
      expect(isVideoFileName('filme.mp4'), isTrue);
      expect(isVideoFileName('FILME.MKV'), isTrue);
    });

    test('recusa fotos, textos e arquivos sem extensão', () {
      expect(isVideoFileName('foto.jpg'), isFalse);
      expect(isVideoFileName('leia.txt'), isFalse);
      expect(isVideoFileName('semextensao'), isFalse);
    });
  });

  group('listVideoFolder', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('browser_test');
      await Directory('${root.path}/zeta').create();
      await Directory('${root.path}/alfa').create();
      await Directory('${root.path}/.oculta').create();
      await File('${root.path}/b.mp4').writeAsString('x');
      await File('${root.path}/a.mkv').writeAsString('x');
      await File('${root.path}/foto.jpg').writeAsString('x');
      await File('${root.path}/.escondido.mp4').writeAsString('x');
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('pastas primeiro, depois vídeos, em ordem; oculta e não-vídeo fora',
        () async {
      final entries = await listVideoFolder(root.path);

      expect(entries.map((e) => e.name), ['alfa', 'zeta', 'a.mkv', 'b.mp4']);
      expect(entries.take(2).every((e) => e.isDirectory), isTrue);
      expect(entries.skip(2).every((e) => !e.isDirectory), isTrue);
    });

    test('pasta inexistente vira lista vazia', () async {
      expect(await listVideoFolder('${root.path}/nao-existe'), isEmpty);
    });
  });
}
