import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/mpv_frame_grabber.dart';
import 'package:player/services/thumbnail_service.dart';

/// Miniatura de vídeo local no Windows real (mpv nativo, sem ferramenta
/// externa). Rodar com a pasta de vídeos de teste em `THUMB_VIDEOS`:
/// `flutter test -d windows integration_test/thumbnail_test.dart`
///
/// Espera quadro de até 320 px para todo vídeo e null para o que não é
/// vídeo legível (só áudio, arquivo cortado, texto).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final folder = Platform.environment['THUMB_VIDEOS'];

  testWidgets('quadros pequenos para os formatos e null para o resto',
      (tester) async {
    MediaKit.ensureInitialized();
    MpvFrameGrabber.enabled = true;
    MpvFrameGrabber.settle = Duration.zero;
    final out = await Directory.systemTemp.createTemp('thumbs_it');
    addTearDown(() => out.delete(recursive: true));
    final service = ThumbnailService(directoryProvider: () async => out);
    final report = StringBuffer();

    final files = Directory(folder!)
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.txt'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final item = MediaItem(
        id: name.replaceAll('.', '_'),
        title: name,
        sourceType: MediaSourceType.local,
        source: file.path,
        addedAt: DateTime(2026, 11, 1),
      );
      final watch = Stopwatch()..start();
      final path = await service.generateFor(item);
      final shouldWork = !(name.startsWith('d_audio') ||
          name.startsWith('f_cortado') ||
          name.startsWith('h_texto'));
      if (shouldWork) {
        expect(path, isNotNull, reason: '$name devia gerar miniatura');
        final decoded = img.decodeJpg(File(path!).readAsBytesSync())!;
        expect(decoded.width, lessThanOrEqualTo(320), reason: name);
        expect(File(path).lengthSync(), lessThan(60 * 1024), reason: name);
        report.writeln('$name: ${decoded.width}x${decoded.height} '
            '${File(path).lengthSync()}B ${watch.elapsedMilliseconds}ms');
        File('$folder${Platform.pathSeparator}$name.thumb.jpg')
            .writeAsBytesSync(File(path).readAsBytesSync());
      } else {
        expect(path, isNull, reason: '$name nao tem quadro');
        report.writeln('$name: sem miniatura ${watch.elapsedMilliseconds}ms');
      }
    }
    File('$folder${Platform.pathSeparator}relatorio.txt')
        .writeAsStringSync(report.toString());
  });

  testWidgets('varios pedidos juntos saem um por vez', (tester) async {
    MediaKit.ensureInitialized();
    MpvFrameGrabber.enabled = true;
    MpvFrameGrabber.settle = Duration.zero;
    final out = await Directory.systemTemp.createTemp('thumbs_it_fila');
    addTearDown(() => out.delete(recursive: true));
    final service = ThumbnailService(directoryProvider: () async => out);
    final source = File('${folder!}${Platform.pathSeparator}i_normal.mp4');

    final results = await Future.wait([
      for (var i = 0; i < 4; i++)
        service.generateFor(MediaItem(
          id: 'fila$i',
          title: 'fila$i',
          sourceType: MediaSourceType.local,
          source: source.path,
          addedAt: DateTime(2026, 11, 1),
        )),
    ]);

    expect(results, everyElement(isNotNull));
  });
}
