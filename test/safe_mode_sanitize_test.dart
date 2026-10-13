import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/startup_guard.dart';

void main() {
  group('sanitizeErrorText (unidade)', () {
    test('texto simples passa intacto', () {
      expect(StartupGuard.sanitizeErrorText('Connection timed out'),
          'Connection timed out');
    });

    test('URL com token vira marcador, sem vazar nada', () {
      final out = StartupGuard.sanitizeErrorText(
          'fetch failed https://midia.test/x.m3u8?token=abc123');
      expect(out, 'fetch failed [url]');
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('http')));
    });

    test('caminho Windows vira marcador', () {
      final out = StartupGuard.sanitizeErrorText(
          r"open failed C:\Users\anna\videos\f.mp4 (acesso negado)");
      expect(out, contains('[caminho]'));
      expect(out, isNot(contains('anna')));
    });

    test('caminho Unix vira marcador', () {
      final out = StartupGuard.sanitizeErrorText(
          'decode failed /data/user/0/com.example.player/cache/a.ts');
      expect(out, contains('[caminho]'));
      expect(out, isNot(contains('com.example.player')));
    });

    test('valor de credencial e redigido, nome mantido', () {
      final out = StartupGuard.sanitizeErrorText(
          'auth failed for sig=deadbeef&user=ana');
      expect(out, contains('sig=[credencial]'));
      expect(out, isNot(contains('deadbeef')));
      expect(out, contains('user=ana'));
    });
  });

  group('recordError sanitizado (integracao)', () {
    test('mensagem e pilha persistem sem URL/caminho/segredo',
        () async {
      final store = InMemoryLocalStore();
      final guard = StartupGuard(store);
      await guard.beginBoot();
      await guard.recordError(
        StateError(
            'load https://midia.test/v.m3u8?token=segredo falhou em /tmp/x/a.ts'),
        StackTrace.fromString(
            'frame0 /data/app/com.example.player/lib/a.so\n'
            'frame1 C:\\dev\\player\\main.dart:12\n'
            'frame2 ok\n'
            'frame3 ok\n'
            'frame4 além do limite'),
      );

      final last = guard.lastError!;
      final message = last['message'] as String;
      final stack = last['stack'] as String;
      expect(message, contains('[url]'));
      expect(message, contains('[caminho]'));
      expect(message, isNot(contains('segredo')));
      expect(message, isNot(contains('http')));
      expect(message, isNot(contains('/tmp')));
      expect(stack, isNot(contains('com.example.player')));
      expect(stack, isNot(contains('C:\\dev')));
      // Pilha segue limitada às 4 primeiras linhas.
      expect(stack, isNot(contains('além do limite')));
    });

    test('classificacao usa o texto original', () async {
      final store = InMemoryLocalStore();
      final guard = StartupGuard(store);
      await guard.beginBoot();
      await guard.recordError(
          StateError('Connection timed out em https://h.test/v?token=t'));
      expect(guard.lastError?['kind'], 'timeout');
      expect(guard.lastError?['message'], isNot(contains('https')));
    });
  });
}
