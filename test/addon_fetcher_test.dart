import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
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
}
