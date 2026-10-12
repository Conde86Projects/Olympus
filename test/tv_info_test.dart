import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/tv_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('player/tv_info');
  const service = TvInfoService();
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('TvInfoService (Leanback)', () {
    test('isTv true quando o nativo diz que é TV', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => true);
      expect(await service.isTv, isTrue);
    });

    test('isTv false quando o nativo diz que não é TV', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await service.isTv, isFalse);
    });

    test('isTv false sem channel (desktop) e em erro', () async {
      // Sem mock: MissingPluginException -> false (desktop nunca é TV).
      expect(await service.isTv, isFalse);
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'ERR'));
      expect(await service.isTv, isFalse);
    });
  });

  group('tvModeAuto (preferência)', () {
    test('padrão liga o automático e desliga o modo TV', () {
      const prefs = UserPreferences();
      expect(prefs.tvModeAuto, isTrue);
      expect(prefs.tvMode, isFalse);
    });

    test('round-trip preserva tvModeAuto', () {
      const prefs = UserPreferences(tvMode: true, tvModeAuto: false);
      final back = UserPreferences.fromMap(prefs.toMap());
      expect(back.tvMode, isTrue);
      expect(back.tvModeAuto, isFalse);
    });

    test('mapa antigo (sem chave) assume automático ligado', () {
      final prefs = UserPreferences.fromMap(const {'tvMode': true});
      expect(prefs.tvModeAuto, isTrue);
    });
  });
}
