import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/focusable_button.dart';

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          faultyIds: const {'bad.addon'},
        ) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
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

  Widget get app => PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: windows,
        addonService: addons,
        startupGuard: guard,
        diagnosticsService: diagnostics,
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Future<void> install(String id,
      {bool active = false, List<String>? platforms}) async {
    final json = demoManifestJson(id: id);
    if (platforms != null) json['supportedPlatforms'] = platforms;
    await addons.install(
      AddonManifest.fromMap(json),
      originTrusted: false,
    );
    if (active) await addons.enable(id);
  }
}

void main() {
  group('tela Add-ons', () {
    testWidgets('vazia explica a ausência', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum add-on instalado'), findsOneWidget);
    });

    testWidgets('lista mostra estados por add-on', (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo', active: true);
      await harness.install('quieto.catalogo');
      await harness.install('bad.addon', active: true);
      await harness.addons.getCatalog('bad.addon');
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      expect(find.text('Catálogo Demo'), findsNWidgets(3));
      expect(find.text('Ativo'), findsOneWidget);
      expect(find.text('Inativo'), findsOneWidget);
      expect(find.text('Erro'), findsOneWidget);
    });

    testWidgets('detalhes mostram identificacao e permissoes',
        (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo');
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Equipe Player'), findsOneWidget);
      expect(find.textContaining('Ler catálogos'), findsOneWidget);
      expect(find.textContaining('Abrir mídias para reprodução'),
          findsOneWidget);
      expect(find.text('Inativo'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aviso legal'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Demonstração sem conteúdo real.'),
          findsOneWidget);
    });

    testWidgets('ativar e desativar pelos detalhes', (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo');
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FocusableButton, 'Ativar'));
      await tester.pumpAndSettle();
      expect(find.text('Ativo'), findsOneWidget);

      await tester.tap(find.widgetWithText(FocusableButton, 'Desativar'));
      await tester.pumpAndSettle();
      expect(find.text('Inativo'), findsOneWidget);
    });

    testWidgets('incompativel mostra o motivo', (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo', platforms: ['android']);
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FocusableButton, 'Ativar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('não é compatível'), findsOneWidget);
      expect(find.text('Inativo'), findsOneWidget);
    });

    testWidgets('remover pede confirmacao e volta a lista vazia',
        (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo');
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FocusableButton, 'Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Remover add-on?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum add-on instalado'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('primeiro item abre com Enter', (tester) async {
      final harness = _Harness();
      await harness.install('demo.catalogo');
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('Equipe Player'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aviso legal'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Demonstração sem conteúdo real.'),
          findsOneWidget);
    });
  });
}
