import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Reduz um quadro JPEG para no máximo [maxWidth] de largura, mantendo a
/// proporção, e devolve outro JPEG. Imagem já menor fica no tamanho. Bytes
/// que não são uma imagem JPEG viram null.
Uint8List? downscaleJpeg(Uint8List bytes, int maxWidth, {int quality = 82}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeJpg(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final resized = decoded.width <= maxWidth
      ? decoded
      : img.copyResize(
          decoded,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// [downscaleJpeg] fora da thread da interface: decodificar um quadro 4K em
/// Dart leva perto de um segundo e travaria a tela.
Future<Uint8List?> downscaleJpegAsync(Uint8List bytes, int maxWidth) =>
    compute(_downscale, (bytes, maxWidth));

Uint8List? _downscale((Uint8List, int) args) =>
    downscaleJpeg(args.$1, args.$2);
