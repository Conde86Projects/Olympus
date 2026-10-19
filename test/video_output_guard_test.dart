import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/video_output_guard.dart';
import 'package:player/services/window_service.dart';

/// Simula um novo arranque sobre o mesmo disco.
Future<VideoOutputGuard> _boot(LocalStore store) async {
  final guard = VideoOutputGuard(store);
  await guard.load();
  return guard;
}

void main() {
  group('VideoOutputGuard', () {
    test('queda unica nao desliga a saida direta', () async {
      final store = InMemoryLocalStore();
      await (await _boot(store)).playbackStarted();
      final next = await _boot(store);
      expect(next.consecutiveCrashes, 1);
      expect(next.autoCompatible, isFalse);
    });

    test('duas quedas seguidas ligam o modo compativel', () async {
      final store = InMemoryLocalStore();
      await (await _boot(store)).playbackStarted();
      await (await _boot(store)).playbackStarted();
      final third = await _boot(store);
      expect(third.autoCompatible, isTrue);
      // Persistente: um arranque limpo nao desfaz sozinho.
      expect((await _boot(store)).autoCompatible, isTrue);
    });

    test('reproducao encerrada normalmente zera a contagem', () async {
      final store = InMemoryLocalStore();
      await (await _boot(store)).playbackStarted();
      final second = await _boot(store);
      await second.playbackStarted();
      await second.playbackStopped();
      await (await _boot(store)).playbackStarted();
      final last = await _boot(store);
      expect(last.consecutiveCrashes, 1);
      expect(last.autoCompatible, isFalse);
    });

    test('ir para segundo plano nao conta como queda', () async {
      final store = InMemoryLocalStore();
      final guard = await _boot(store);
      await guard.playbackStarted();
      guard.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      final next = await _boot(store);
      expect(next.consecutiveCrashes, 0);
    });

    test('voltar do segundo plano religa a marca', () async {
      final store = InMemoryLocalStore();
      final guard = await _boot(store);
      await guard.playbackStarted();
      guard.didChangeAppLifecycleState(AppLifecycleState.paused);
      guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect((await _boot(store)).consecutiveCrashes, 1);
    });

    test('reset esquece as quedas', () async {
      final store = InMemoryLocalStore();
      await (await _boot(store)).playbackStarted();
      await (await _boot(store)).playbackStarted();
      final guard = await _boot(store);
      expect(guard.autoCompatible, isTrue);
      await guard.reset();
      expect((await _boot(store)).autoCompatible, isFalse);
    });
  });

  group('preferencia de video compativel', () {
    test('padrao desligado e round-trip', () {
      expect(const UserPreferences().compatibleVideoOutput, isFalse);
      final prefs =
          const UserPreferences().copyWith(compatibleVideoOutput: true);
      expect(UserPreferences.fromMap(prefs.toMap()).compatibleVideoOutput,
          isTrue);
      expect(UserPreferences.fromMap(const {}).compatibleVideoOutput,
          isFalse);
    });

    Future<InMemoryPreferencesService> pumpSettings(
      WidgetTester tester, {
      VideoOutputGuard? guard,
    }) async {
      final preferences = InMemoryPreferencesService();
      await preferences
          .update(preferences.current.copyWith(showOnboarding: false));
      final library = InMemoryLibraryService();
      final history = InMemoryHistoryService();
      const player = NoOpMediaPlayerService();
      final addons = LocalAddonService(InMemoryLocalStore());
      final startup = StartupGuard(InMemoryLocalStore());
      await tester.pumpWidget(PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: NoOpWindowService(),
        addonService: addons,
        startupGuard: startup,
        diagnosticsService: DiagnosticsService(
          store: InMemoryLocalStore(),
          preferences: preferences,
          library: library,
          history: history,
          player: player,
          addons: addons,
          guard: startup,
        ),
        videoOutputGuard: guard,
      ));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed(AppRoutes.settings);
      await tester.pumpAndSettle();
      return preferences;
    }

    testWidgets('opcao nao aparece no desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpSettings(tester);
        expect(find.text('Modo de vídeo compatível', skipOffstage: false),
            findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android: interruptor grava a preferencia', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final prefs = await pumpSettings(tester);
        final tile = find.text('Modo de vídeo compatível');
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(prefs.current.compatibleVideoOutput, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android: desligar apos quedas esquece a guarda',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final store = InMemoryLocalStore();
        await (await _boot(store)).playbackStarted();
        await (await _boot(store)).playbackStarted();
        final guard = await _boot(store);
        await pumpSettings(tester, guard: guard);
        final tile = find.text('Modo de vídeo compatível');
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        expect(find.textContaining('Ligado sozinho'), findsOneWidget);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(guard.autoCompatible, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
