import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/player/player_screen.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
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

class _Harness {
  _Harness({Set<String> faultyIds = const {'bad.addon'}})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          faultyIds: faultyIds,
        ) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  final LocalAddonService addons;
  final StartupGuard guard;

  DiagnosticsService get diagnostics => DiagnosticsService(
        store: InMemoryLocalStore(),
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
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

  /// Instala e ativa um add-on; se defeituoso, dispara a falha pelo
  /// catalogo (vira estado de erro, nunca excecao).
  Future<void> install(String id, {bool triggerFault = false}) async {
    await addons.install(
      AddonManifest.fromMap(demoManifestJson(id: id)),
      originTrusted: false,
    );
    await addons.enable(id);
    if (triggerFault) await addons.getCatalog(id);
  }
}

void main() {
  group('isolamento de add-on com defeito', () {
    testWidgets('app abre e player local funciona com add-on defeituoso',
        (tester) async {
      final harness = _Harness();
      await harness.install('bad.addon', triggerFault: true);
      await harness.pump(tester);

      // Inicial utilizavel: navegacao intacta.
      expect(find.byTooltip('Add-ons'), findsOneWidget);

      // Player local abre um arquivo mesmo com o defeito presente.
      final item = MediaItem(
        id: 'local',
        title: 'Vídeo local',
        sourceType: MediaSourceType.local,
        source: r'C:\Vídeos\exemplo.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      await harness.library.upsert(item);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
    });

    testWidgets('erro mostra diagnóstico e desativa pela UI', (tester) async {
      final harness = _Harness();
      await harness.install('bad.addon', triggerFault: true);
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      expect(find.text('Erro'), findsOneWidget);

      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar o catálogo deste add-on.'),
          findsOneWidget);

      await tester.tap(find.text('Desativar'));
      await tester.pumpAndSettle();
      expect(find.text('Ativar'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Inativo'), findsOneWidget);
      expect(harness.addons.getStatus('bad.addon'), AddonState.inactive);
    });

    testWidgets('saudável segue ativo ao lado do defeituoso', (tester) async {
      final harness = _Harness();
      await harness.install('good.catalogo');
      await harness.install('bad.addon', triggerFault: true);
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      expect(find.text('Ativo'), findsOneWidget);
      expect(find.text('Erro'), findsOneWidget);

      // O saudavel continua operando: catalogo cheio, sem erro.
      final catalog = await harness.addons.getCatalog('good.catalogo');
      expect(catalog, hasLength(2));
      expect(
          harness.addons.getStatus('good.catalogo'), AddonState.active);
    });

    test('falha vira AddonError controlado, nunca exceção crua', () async {
      final harness = _Harness(faultyIds: const {'bad.um', 'bad.dois'});
      await harness.install('bad.um', triggerFault: true);
      await harness.install('bad.dois');

      // Catalogo e busca: devolvem vazio, nao lancam.
      expect(await harness.addons.getCatalog('bad.um'), isEmpty);
      expect(await harness.addons.search('bad.um', 'x'), isEmpty);

      // Reproducao em add-on ja isolado: indisponivel controlado.
      try {
        await harness.addons
            .resolvePlayback('bad.um', demoCatalog().first);
        fail('reprodução deveria falhar');
      } catch (error) {
        expect(error, isA<AddonError>());
        expect(
            (error as AddonError).code, 'addon.unavailable');
      }

      // Reproducao dispara o defeito e isola: controlado do mesmo jeito.
      try {
        await harness.addons
            .resolvePlayback('bad.dois', demoCatalog().first);
        fail('reprodução deveria falhar');
      } catch (error) {
        expect(error, isA<AddonError>());
        expect(
            (error as AddonError).code, 'addon.unavailable');
      }
      expect(harness.addons.getStatus('bad.dois'), AddonState.error);
    });
  });
}
