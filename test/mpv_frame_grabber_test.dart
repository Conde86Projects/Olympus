import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/mpv_frame_grabber.dart';

void main() {
  group('MpvFrameGrabber', () {
    test('desligado por padrao: devolve null sem tocar no motor', () async {
      expect(MpvFrameGrabber.enabled, isFalse);

      expect(await MpvFrameGrabber.grab('/qualquer.mp4', 320), isNull);
    });

    test('um quadro por vez, na ordem dos pedidos', () async {
      final order = <String>[];
      final gate = Completer<void>();

      Future<int> task(String name, {Completer<void>? wait}) =>
          MpvFrameGrabber.serialized(() async {
            order.add('inicio $name');
            await wait?.future;
            order.add('fim $name');
            return order.length;
          });

      final first = task('a', wait: gate);
      final second = task('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, ['inicio a']);

      gate.complete();
      await Future.wait([first, second]);

      expect(order, ['inicio a', 'fim a', 'inicio b', 'fim b']);
    });

    test('falha de um pedido nao trava os seguintes', () async {
      final failing = MpvFrameGrabber.serialized<int>(
          () async => throw StateError('falhou'));
      await expectLater(failing, throwsStateError);

      expect(await MpvFrameGrabber.serialized(() async => 7), 7);
    });
  });
}
