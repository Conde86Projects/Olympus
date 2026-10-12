import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/media_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('player/media_permission');
  const service = MediaPermissionService();
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mock(String Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  group('MediaPermissionService (F8-runtime)', () {
    test('hasAccess true quando o nativo diz granted', () async {
      mock((call) => 'granted');
      expect(await service.hasAccess, isTrue);
    });

    test('hasAccess false quando o nativo diz denied', () async {
      mock((call) => 'denied');
      expect(await service.hasAccess, isFalse);
    });

    test('ensureAccess não pede quando já tem acesso', () async {
      var calls = 0;
      mock((call) {
        calls++;
        return 'granted';
      });
      expect(await service.ensureAccess(), isTrue);
      expect(calls, 1); // só o status; sem request.
    });

    test('ensureAccess pede e devolve o resultado', () async {
      final seen = <String>[];
      mock((call) {
        seen.add(call.method);
        return call.method == 'status' ? 'denied' : 'granted';
      });
      expect(await service.ensureAccess(), isTrue);
      expect(seen, ['status', 'request']);
    });

    test('ensureAccess falso quando o usuário nega', () async {
      mock((call) => 'denied');
      expect(await service.ensureAccess(), isFalse);
    });

    test('sem channel (desktop) libera o acesso', () async {
      // Sem mock: MissingPluginException -> true (não trava; o F9
      // explica se o open falhar de verdade).
      expect(await service.hasAccess, isTrue);
      expect(await service.ensureAccess(), isTrue);
    });
  });
}

