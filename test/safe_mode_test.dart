import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Simula um arranque: guarda novo sobre o mesmo armazenamento.
StartupGuard bootOn(LocalStore store) => StartupGuard(store);

Future<LocalAddonService> installedOn(LocalStore store) async {
  final addons = LocalAddonService(store, platform: 'windows');
  await addons.install(
    AddonManifest.fromMap(demoManifestJson()),
    originTrusted: false,
  );
  return addons;
}

void main() {
  group('StartupGuard contador e modo seguro', () {
    test('primeiro arranque limpo nao entra em modo seguro', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      expect(guard.safeMode, isFalse);
      expect(guard.safeModeReason, isNull);

      await guard.markCleanBoot();
      expect(guard.consecutiveFailures, 0);
    });

    test('2 arranques sujos engatam o modo seguro no seguinte', () async {
      final store = InMemoryLocalStore();
      await bootOn(store).beginBoot();
      final second = bootOn(store);
      await second.beginBoot();
      // So 1 falha observada: ainda normal.
      expect(second.safeMode, isFalse);

      final third = bootOn(store);
      await third.beginBoot();
      expect(third.safeMode, isTrue);
      expect(third.safeModeReason, SafeModeReason.crashes);
      expect(third.consecutiveFailures, 2);
    });

    test('arranque limpo zera as falhas acumuladas', () async {
      final store = InMemoryLocalStore();
      await bootOn(store).beginBoot();
      final dirty = bootOn(store);
      await dirty.beginBoot();
      await dirty.markCleanBoot();

      final next = bootOn(store);
      await next.beginBoot();
      expect(next.safeMode, isFalse);
      expect(next.consecutiveFailures, 0);
    });

    test('modo manual vale sem falhas e persiste', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      await guard.setManualSafeMode(true);
      expect(guard.safeMode, isTrue);
      expect(guard.safeModeReason, SafeModeReason.manual);

      final next = bootOn(store);
      await next.beginBoot();
      expect(next.safeMode, isTrue);
      expect(next.safeModeReason, SafeModeReason.manual);

      await next.setManualSafeMode(false);
      await next.markCleanBoot();
      final clean = bootOn(store);
      await clean.beginBoot();
      expect(clean.safeMode, isFalse);
    });

    test('documento corrompido volta ao padrao seguro', () async {
      final store = InMemoryLocalStore();
      await store.write('startup_guard', {
        'pendingBoots': 'muito',
        'manualSafeMode': 'talvez',
      });
      final guard = bootOn(store);
      await guard.beginBoot();
      expect(guard.safeMode, isFalse);
      expect(guard.consecutiveFailures, 0);
    });
  });

  group('StartupGuard erros e recuperacao', () {
    test('recordError persiste mensagem truncada', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      await guard.recordError(StateError('x' * 500));

      final next = bootOn(store);
      await next.beginBoot();
      final last = next.lastError!;
      expect((last['message'] as String).length, 200);
      expect(last['at'], isNotNull);
    });

    test('recordError classifica e persiste o tipo', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      await guard.recordError(StateError('Connection timed out'));
      expect(guard.lastError?['kind'], 'timeout');

      final next = bootOn(store);
      await next.beginBoot();
      expect(next.lastError?['kind'], 'timeout');
    });

    test('clearEphemeral limpa o ultimo erro', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      await guard.recordError('boom');
      await guard.clearEphemeral();
      expect(guard.lastError, isNull);
    });

    test('desativar ultima alteracao marca inativo no documento', () async {
      final store = InMemoryLocalStore();
      final addons = await installedOn(store);
      await addons.enable('demo.catalogo');

      final guard = bootOn(store);
      final change = await guard.readLastChange();
      expect(change!.id, 'demo.catalogo');
      expect(change.name, 'Catálogo Demo');

      expect(await guard.disableLastChange(), isTrue);

      // Prova pelo documento: servico novo, sem memoria anterior.
      final fresh = LocalAddonService(store, platform: 'windows');
      await fresh.load();
      expect(fresh.getStatus('demo.catalogo'), AddonState.inactive);

      // Registro consumido: segunda chamada nao faz nada.
      expect(await guard.disableLastChange(), isFalse);
      expect(await guard.readLastChange(), isNull);
    });

    test('desativar sem alteracao nao faz nada', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      expect(await guard.readLastChange(), isNull);
      expect(await guard.disableLastChange(), isFalse);
    });

    test('clearRecoveryData apaga o estado do guarda', () async {
      final store = InMemoryLocalStore();
      final guard = bootOn(store);
      await guard.beginBoot();
      await guard.setManualSafeMode(true);
      await guard.recordError('boom');
      await guard.clearRecoveryData();

      expect(guard.safeMode, isFalse);
      expect(guard.lastError, isNull);
      expect(await store.read('startup_guard'), isNull);
    });
  });

  group('faixa de modo seguro', () {
    testWidgets('falhas repetidas mostram faixa e pulam add-ons',
        (tester) async {
      final harness = _WidgetHarness();
      // Persistidos de um arranque anterior (com ultima alteracao).
      await harness.setup.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: false,
      );
      await harness.setup.enable('demo.catalogo');
      await harness.simulateCrashes(2);
      await harness.pump(tester);

      expect(
          find.text(
              'Modo seguro: add-ons não carregados (2 falhas no arranque).'),
          findsOneWidget);
      expect(find.text('Última alteração: Catálogo Demo.'),
          findsOneWidget);

      // Servico do app nao carregado: lista vazia apesar do documento.
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum add-on instalado'), findsOneWidget);
    });

    testWidgets('desativar pela faixa marca inativo no documento',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.setup.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: false,
      );
      await harness.setup.enable('demo.catalogo');
      await harness.simulateCrashes(2);
      await harness.pump(tester);

      await tester.tap(find.text('Desativar última alteração'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Última alteração desativada.'),
          findsOneWidget);

      final fresh = LocalAddonService(harness.store, platform: 'windows');
      await fresh.load();
      expect(fresh.getStatus('demo.catalogo'), AddonState.inactive);
    });

    testWidgets('biblioteca e historico seguem intactos no modo seguro',
        (tester) async {
      final harness = _WidgetHarness();
      final item = MediaItem(
        id: 'v1',
        title: 'Vídeo salvo',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/v.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      await harness.library.upsert(item);
      await harness.history.record(HistoryEntry(
        mediaId: 'v1',
        accessedAt: DateTime(2026, 1, 2),
        position: const Duration(minutes: 3),
      ));
      await harness.simulateCrashes(2);
      await harness.pump(tester);

      expect(find.textContaining('Modo seguro'), findsWidgets);
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(find.text('Vídeo salvo'), findsOneWidget);
    });

    testWidgets('modo manual mostra motivo manual', (tester) async {
      final harness = _WidgetHarness();
      await harness.guard.beginBoot();
      await harness.guard.setManualSafeMode(true);
      await harness.pump(tester);

      expect(
          find.text(
              'Modo seguro ativado manualmente: add-ons não carregados.'),
          findsOneWidget);
    });

    testWidgets('arranque normal nao mostra faixa', (tester) async {
      final harness = _WidgetHarness();
      await harness.guard.beginBoot();
      await harness.guard.markCleanBoot();
      await harness.pump(tester);

      expect(find.textContaining('Modo seguro'), findsNothing);
    });
  });
}

/// Arranque simulado: o [setup] persiste como um arranque anterior, o
/// [addons] do app nasce descarregado (o main pula o load em modo
/// seguro) e o [guard] controla o modo.
class _WidgetHarness {
  _WidgetHarness()
      : store = InMemoryLocalStore(),
        preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService() {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
    setup = LocalAddonService(store, platform: 'windows');
    addons = LocalAddonService(store, platform: 'windows');
    guard = StartupGuard(store);
  }

  final InMemoryLocalStore store;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  late final LocalAddonService setup;
  late final LocalAddonService addons;
  late final StartupGuard guard;

  DiagnosticsService get diagnostics => DiagnosticsService(
        store: store,
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      );

  /// Simula [n] arranques sujos e posiciona o guarda no arranque
  /// seguinte (o que o usuario veria).
  Future<void> simulateCrashes(int n) async {
    for (var i = 0; i < n; i++) {
      await StartupGuard(store).beginBoot();
    }
    await guard.beginBoot();
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PlayerApp(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: windows,
      addonService: addons,
      startupGuard: guard,
      diagnosticsService: diagnostics,
    ));
    await tester.pumpAndSettle();
  }
}
