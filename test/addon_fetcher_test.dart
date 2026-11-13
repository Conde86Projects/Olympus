import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/internal_address.dart';
import 'package:player/services/addon_fetcher.dart';

/// Serve respostas programadas em loopback para exercitar o
/// [HttpAddonFetcher] sem rede externa.
Future<HttpServer> serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

String urlOf(HttpServer server, [String path = '/']) =>
    'http://${server.address.host}:${server.port}$path';

Future<AddonError> expectFetchFails(
  HttpAddonFetcher fetcher,
  String url,
) async {
  try {
    await fetcher.fetchText(url);
  } on AddonError catch (error) {
    expect(error.code, 'addon.fetch-failed');
    return error;
  }
  fail('busca deveria ter falhado: $url');
}

void main() {
  rebindingTests();
  group('HttpAddonFetcher', () {
    test('baixa o corpo de um 200 com JSON', () async {
      final server = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"id":"demo.x"}');
        await request.response.close();
      });
      addTearDown(server.close);

      final body = await const HttpAddonFetcher(allowPrivate: true).fetchText(urlOf(server));
      expect(jsonDecode(body), {'id': 'demo.x'});
    });

    test('rejeita URL invalida antes de abrir socket', () async {
      const fetcher = HttpAddonFetcher();
      for (final bad in [
        'não é url',
        'ftp://exemplo.com/man.json',
        'file:///etc/passwd',
        '',
      ]) {
        final error = await expectFetchFails(fetcher, bad);
        expect(error.message, contains('inválido'));
      }
    });

    test('HTTP diferente de 200 vira erro legivel', () async {
      final server = await serve((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(server.close);

      final error = await expectFetchFails(
        const HttpAddonFetcher(allowPrivate: true),
        urlOf(server),
      );
      expect(error.message, contains('404'));
    });

    test('corpo acima do teto e recusado durante o stream', () async {
      final server = await serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        // Sem content-length: força o teto do stream, não o precheck.
        request.response.headers.chunkedTransferEncoding = true;
        request.response.write('{"pad":"');
        request.response.write('x' * (300 * 1024));
        request.response.write('"}');
        await request.response.close();
      });
      addTearDown(server.close);

      final error = await expectFetchFails(
        const HttpAddonFetcher(allowPrivate: true),
        urlOf(server),
      );
      expect(error.message, contains('grande demais'));
    });

    test('resposta lenta estoura o timeout configurado', () async {
      final server = await serve((request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        request.response.statusCode = HttpStatus.ok;
        request.response.write('tarde demais');
        await request.response.close();
      });
      addTearDown(server.close);

      final error = await expectFetchFails(
        const HttpAddonFetcher(timeout: Duration(milliseconds: 100), allowPrivate: true),
        urlOf(server),
      );
      expect(error.message, contains('demorou'));
    });

    test('bytes que nao sao UTF-8 viram erro, nao excecao crua', () async {
      final server = await serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.add([0xFF, 0xFE, 0x00]);
        await request.response.close();
      });
      addTearDown(server.close);

      final error = await expectFetchFails(
        const HttpAddonFetcher(allowPrivate: true),
        urlOf(server),
      );
      expect(error.message, contains('texto válido'));
    });

    test('porta fechada vira erro de conexao', () async {
      // Liga e desliga um servidor so para reservar uma porta que o
      // SO vai recusar (RST) em vez de filtrar.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close(force: true);
      final error = await expectFetchFails(
        const HttpAddonFetcher(timeout: Duration(seconds: 5), allowPrivate: true),
        'http://127.0.0.1:$port/man.json',
      );
      expect(error.message, contains('conexão'));
    });
  });

  group('SSRF: internos e reservados bloqueiam (5C)', () {
    test('tabela de bloqueio por endereco', () {
      final blocked = [
        '127.0.0.1',
        '127.1.2.3',
        '10.0.0.1',
        '10.255.255.255',
        '172.16.0.0',
        '172.31.255.255',
        '192.168.0.1',
        '192.168.1.8',
        '0.0.0.0',
        '169.254.10.20',
        '224.0.0.1',
        '::1',
        '::',
        'fe80::1',
        'fc00::1',
        'ff02::1',
        '::ffff:10.0.0.1',
        '::ffff:127.0.0.1',
      ];
      for (final ip in blocked) {
        expect(isBlockedInternetAddress(InternetAddress(ip)), isTrue,
            reason: ip);
      }
      final open = [
        '8.8.8.8',
        '1.1.1.1',
        '11.0.0.1',
        '172.15.255.255',
        '172.32.0.0',
        '192.167.1.1',
        '2001:4860:4860::8888',
        '::ffff:8.8.8.8',
      ];
      for (final ip in open) {
        expect(isBlockedInternetAddress(InternetAddress(ip)), isFalse,
            reason: ip);
      }
    });

    test('literal interno bloqueia sem abrir socket', () async {
      // Fetcher padrao (producao): nada aqui encosta na rede.
      const fetcher = HttpAddonFetcher();
      for (final url in [
        'http://127.0.0.1/man.json',
        'http://10.0.0.1/man.json',
        'http://172.16.5.4:8080/man.json',
        'http://192.168.1.8/man.json',
        'http://0.0.0.0/man.json',
        'http://[::1]/man.json',
        'http://[fe80::1]/man.json',
      ]) {
        final error = await expectFetchFails(fetcher, url);
        expect(error.message, contains('reservado'), reason: url);
      }
    });

    test('localhost resolve interno e bloqueia', () async {
      // hosts do SO, sem rede externa.
      const fetcher = HttpAddonFetcher();
      final error =
          await expectFetchFails(fetcher, 'http://localhost/man.json');
      expect(error.message, contains('reservado'));
    });

    test('redirect valido e seguido', () async {
      final target = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"ok":true}');
        await request.response.close();
      });
      addTearDown(target.close);
      final source = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, urlOf(target, '/f.json'));
        await request.response.close();
      });
      addTearDown(source.close);

      final body = await const HttpAddonFetcher(allowPrivate: true)
          .fetchText(urlOf(source));
      expect(jsonDecode(body), {'ok': true});
    });

    test('redirect em loop estoura o limite', () async {
      final server = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/volta');
        await request.response.close();
      });
      addTearDown(server.close);

      final error = await expectFetchFails(
        const HttpAddonFetcher(allowPrivate: true),
        urlOf(server),
      );
      expect(error.message, contains('Redirecionamentos demais'));
    });

    test('tabela de resolucao de redirect', () {
      final base = Uri.parse('https://a.exemplo.com/dir/f.json');
      expect(resolveFeedRedirect(base, '/outro.json'),
          Uri.parse('https://a.exemplo.com/outro.json'));
      expect(resolveFeedRedirect(base, 'https://b.exemplo.com/x'),
          Uri.parse('https://b.exemplo.com/x'));
      for (final bad in [null, '', 'ftp://a.exemplo.com/x', 'file:///x']) {
        expect(
          () => resolveFeedRedirect(base, bad),
          throwsA(isA<AddonError>().having(
              (e) => e.code, 'code', 'addon.fetch-failed')),
          reason: '$bad',
        );
      }
    });
  });

  group('fetchBytes (T3)', () {
    test('baixa os bytes de um 200 com progresso', () async {
      final payload = List<int>.generate(4096, (i) => i % 256);
      final server = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..headers.contentLength = payload.length
          ..add(payload);
        await request.response.close();
      });
      addTearDown(server.close);

      final seen = <String>[];
      final bytes = await const HttpAddonFetcher(allowPrivate: true)
          .fetchBytes(urlOf(server), onProgress: (received, total) {
        seen.add('$received/$total');
      });
      expect(bytes, payload);
      expect(seen, isNotEmpty);
      expect(seen.last, '${payload.length}/${payload.length}');
    });

    test('rejeita URL invalida antes de abrir socket', () async {
      const fetcher = HttpAddonFetcher();
      for (final bad in [
        'não é url',
        'ftp://exemplo.com/p.zip',
        '',
      ]) {
        try {
          await fetcher.fetchBytes(bad);
          fail('busca deveria ter falhado: $bad');
        } on AddonError catch (error) {
          expect(error.message, contains('inválido'), reason: bad);
        }
      }
    });

    test('redirect valido e seguido', () async {
      final payload = List<int>.generate(1024, (i) => i % 251);
      final target = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..add(payload);
        await request.response.close();
      });
      addTearDown(target.close);
      final source = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, urlOf(target, '/p.zip'));
        await request.response.close();
      });
      addTearDown(source.close);

      final bytes = await const HttpAddonFetcher(allowPrivate: true)
          .fetchBytes(urlOf(source));
      expect(bytes, payload);
    });

    test('content-length acima do teto recusa sem baixar', () async {
      final server = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = 11 * 1024 * 1024
          ..add([1, 2, 3]);
        await request.response.flush();
        // Segura a conexão: o cliente já recusou no precheck.
        await Completer<void>().future;
      });
      addTearDown(() => server.close(force: true));

      try {
        await const HttpAddonFetcher(allowPrivate: true)
            .fetchBytes(urlOf(server));
        fail('busca deveria ter falhado');
      } on AddonError catch (error) {
        expect(error.message, 'O pacote é grande demais (limite de 10 MB).');
      }
    });

    test('corpo acima de 10 MB e recusado durante o stream', () async {
      final server = await serve((request) async {
        try {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.chunkedTransferEncoding = true;
          for (var i = 0; i < 11 * 1024; i++) {
            request.response.add(List<int>.filled(1024, 0));
            await request.response.flush();
          }
          await request.response.close();
        } catch (_) {}
      });
      addTearDown(server.close);

      try {
        await const HttpAddonFetcher(allowPrivate: true)
            .fetchBytes(urlOf(server));
        fail('busca deveria ter falhado');
      } on AddonError catch (error) {
        expect(error.message, 'O pacote é grande demais (limite de 10 MB).');
      }
    });

    test('cancelar no meio vira motivo proprio', () async {
      final server = await serve((request) async {
        try {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.chunkedTransferEncoding = true;
          for (var i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            request.response.add(List<int>.filled(64 * 1024, 7));
            await request.response.flush();
          }
          await request.response.close();
        } catch (_) {}
      });
      addTearDown(server.close);

      final cancel = Completer<void>();
      var calls = 0;
      try {
        await const HttpAddonFetcher(allowPrivate: true).fetchBytes(
          urlOf(server),
          onProgress: (received, total) {
            calls++;
            if (!cancel.isCompleted) cancel.complete();
          },
          cancel: cancel.future,
        );
        fail('busca deveria ter cancelado');
      } on AddonError catch (error) {
        expect(error.code, 'addon.fetch-failed');
        expect(error.message, 'Download cancelado.');
      }
      expect(calls, greaterThan(0));
    });
  });
}

void rebindingTests() {
  group('resolvePublicAddress', () {
    Future<List<InternetAddress>> answer(List<String> ips) async =>
        [for (final ip in ips) InternetAddress(ip)];

    test('devolve o endereço público que vai ser usado na conexão',
        () async {
      final address = await resolvePublicAddress('exemplo.org',
          timeout: const Duration(seconds: 1),
          lookup: (_) => answer(['93.184.216.34']));
      expect(address.address, '93.184.216.34');
    });

    test('resposta mista com um interno falha fechado', () async {
      await expectLater(
        resolvePublicAddress('exemplo.org',
            timeout: const Duration(seconds: 1),
            lookup: (_) => answer(['93.184.216.34', '192.168.0.1'])),
        throwsA(isA<AddonError>()),
      );
    });

    test('só interno e resposta vazia falham', () async {
      for (final ips in [<String>['10.0.0.5'], <String>[]]) {
        await expectLater(
          resolvePublicAddress('exemplo.org',
              timeout: const Duration(seconds: 1),
              lookup: (_) => answer(ips)),
          throwsA(isA<AddonError>()),
          reason: '$ips',
        );
      }
    });
  });
}
