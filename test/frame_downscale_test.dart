import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:player/core/utils/frame_downscale.dart';

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('downscaleJpeg', () {
    test('reduz para a largura maxima mantendo a proporcao', () {
      final out = downscaleJpeg(_jpeg(1280, 720), 320)!;

      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 320);
      expect(decoded.height, 180);
    });

    test('quadro vertical tambem respeita a largura', () {
      final decoded = img.decodeJpg(downscaleJpeg(_jpeg(720, 1280), 320)!)!;

      expect(decoded.width, 320);
      expect(decoded.height, 569);
    });

    test('nao amplia imagem menor que o limite', () {
      final decoded = img.decodeJpg(downscaleJpeg(_jpeg(200, 100), 320)!)!;

      expect(decoded.width, 200);
      expect(decoded.height, 100);
    });

    test('o resultado e bem menor que o quadro cheio', () {
      final full = _jpeg(1920, 1080);

      expect(downscaleJpeg(full, 320)!.length, lessThan(full.length));
    });

    test('bytes que nao sao imagem viram null', () {
      expect(downscaleJpeg(Uint8List.fromList([1, 2, 3]), 320), isNull);
      expect(downscaleJpeg(Uint8List(0), 320), isNull);
    });

    test('a versao assincrona devolve o mesmo resultado', () async {
      final out = await downscaleJpegAsync(_jpeg(1280, 720), 320);

      expect(img.decodeJpg(out!)!.width, 320);
      expect(await downscaleJpegAsync(Uint8List.fromList([1]), 320), isNull);
    });
  });
}
