import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/hls_cold_probe.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/features/player/hls_cold_warmer.dart';

const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=700000,RESOLUTION=640x360
v0/p.m3u8
''';
const _url = 'https://exemplo.com/master.m3u8';

Duration get _total => HlsColdProbe.warmDelays
    .fold(const Duration(seconds: 1), (sum, delay) => sum + delay);

void main() {
  late int fetches;
  late List<List<HlsVariant>> delivered;
  late bool needed;

  HlsColdWarmer warmer(Future<String> Function(Uri) fetch) => HlsColdWarmer(
        fetchText: (uri) {
          fetches++;
          return fetch(uri);
        },
        stillNeeded: () => needed,
        onVariants: delivered.add,
      );

  setUp(() {
    fetches = 0;
    delivered = [];
    needed = true;
  });

  test('falha sempre: tenta so o limite e para', () {
    fakeAsync((async) {
      warmer((_) => throw const SocketException('sem rede')).start(_url);
      async.elapse(_total * 2);
      expect(fetches, HlsColdProbe.warmDelays.length);
      expect(delivered, isEmpty);
    });
  });

  test('entrega ao recuperar e nao tenta mais', () {
    fakeAsync((async) {
      warmer((_) async {
        if (fetches < 2) throw const SocketException('rede fria');
        return _master;
      }).start(_url);
      async.elapse(_total * 2);
      expect(fetches, 2);
      expect(delivered.single, hasLength(1));
    });
  });

  test('playlist simples e definitiva: sem nova tentativa', () {
    fakeAsync((async) {
      warmer((_) async => '#EXTM3U\n#EXTINF:4,\ns.ts\n').start(_url);
      async.elapse(_total * 2);
      expect(fetches, 1);
      expect(delivered, isEmpty);
    });
  });

  test('cancelar descarta a busca em andamento', () {
    fakeAsync((async) {
      final pending = Completer<String>();
      final subject = warmer((_) => pending.future)..start(_url);
      async.elapse(HlsColdProbe.warmDelays.first);
      expect(fetches, 1);

      subject.cancel();
      pending.complete(_master);
      async.elapse(_total * 2);
      expect(delivered, isEmpty);
      expect(fetches, 1);
    });
  });

  test('nova abertura abandona a anterior', () {
    fakeAsync((async) {
      final first = Completer<String>();
      final subject = warmer((uri) async {
        if (uri.path == '/velho.m3u8') return first.future;
        return _master;
      })..start('https://exemplo.com/velho.m3u8');
      async.elapse(HlsColdProbe.warmDelays.first);

      subject.start(_url);
      first.complete(_master);
      async.flushMicrotasks();
      expect(delivered, isEmpty);

      async.elapse(HlsColdProbe.warmDelays.first);
      expect(delivered, hasLength(1));
    });
  });

  test('variantes obtidas por outro caminho param as tentativas', () {
    fakeAsync((async) {
      warmer((_) async {
        needed = false;
        throw const SocketException('rede fria');
      }).start(_url);
      async.elapse(_total * 2);
      expect(fetches, 1);
      expect(delivered, isEmpty);
    });
  });
}
