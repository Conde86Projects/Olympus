import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_fetcher.dart';
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

class _FakeFetcher extends AddonFetcher {
  _FakeFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url, {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        bodies = {} {
    addons = LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: _FakeFetcher(bodies),
    );
    preferences.update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  final StartupGuard guard;
  final Map<String, String> bodies;
  late final LocalAddonService addons;

  static const updateUrl = 'https://exemplo.com/demo/manifest.json';

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

  Future<void> install({String version = '1.0.0'}) async {
    final json = demoManifestJson(version: version);
    json['updateUrl'] = updateUrl;
    await addons.install(
      AddonManifest.fromMap(json),
      originTrusted: false,
    );
  }

  void serve({String version = '1.1.0', List<String>? platforms}) {
    final json = demoManifestJson(version: version);
    json['updateUrl'] = updateUrl;
    json['changelog'] = 'Novidades da $version.';
    if (platforms != null) json['supportedPlatforms'] = platforms;
    bodies[updateUrl] = jsonEncode(json);
  }

  /// Abre Add-ons > Atualizações (a tela verifica ao abrir).
  Future<void> openUpdates(WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Atualizações'));
    await tester.pumpAndSettle();
  }

  String get installedVersion =>
      addons.findById('demo.catalogo')!.manifest.version;
}

/// Botão dentro do diálogo de confirmação (o cartão ao fundo tem um
/// botão com o mesmo texto).
Finder dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, label),
    );


void main() {
  group('tela de atualizações', () {
    testWidgets('sem pendências mostra tudo atualizado', (tester) async {
      final harness = _Harness();
      await harness.install();
      await harness.openUpdates(tester);

      expect(find.text('Tudo atualizado'), findsOneWidget);
    });

    testWidgets('lista antes/depois, changelog e plataformas',
        (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.openUpdates(tester);

      expect(find.text('Disponíveis (1)'), findsOneWidget);
      expect(find.text('v1.0.0 → v1.1.0'), findsOneWidget);
      expect(find.text('Novidades da 1.1.0.'), findsOneWidget);
      expect(find.text('Plataformas: windows, linux, macos, android'),
          findsOneWidget);
    });

    testWidgets('atualizar pede confirmação e aplica', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.openUpdates(tester);

      await tester.tap(find.widgetWithText(FocusableButton, 'Atualizar'));
      await tester.pumpAndSettle();
      expect(find.text('Atualizar add-on?'), findsOneWidget);
      expect(find.textContaining('v1.0.0 → v1.1.0'), findsWidgets);
      expect(find.textContaining('Novidades da 1.1.0.'), findsWidgets);

      await tester.tap(dialogButton('Atualizar'));
      await tester.pumpAndSettle();

      expect(harness.installedVersion, '1.1.0');
      expect(find.text('Catálogo Demo atualizado para v1.1.0.'),
          findsOneWidget);
      expect(find.text('Disponíveis (1)'), findsNothing);
      // Backup guardado: rollback passa a ser oferecido.
      expect(find.text('Versão anterior guardada'), findsOneWidget);
      expect(find.text('Voltar para v1.0.0'), findsOneWidget);
    });

    testWidgets('cancelar a confirmação não aplica', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.openUpdates(tester);

      await tester.tap(find.widgetWithText(FocusableButton, 'Atualizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(harness.installedVersion, '1.0.0');
      expect(find.text('v1.0.0 → v1.1.0'), findsOneWidget);
    });

    testWidgets('adiar remove e não reoferece', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.openUpdates(tester);

      await tester.tap(find.widgetWithText(FocusableButton, 'Adiar'));
      await tester.pumpAndSettle();

      expect(find.text('Tudo atualizado'), findsOneWidget);
      expect(harness.installedVersion, '1.0.0');
      final info = harness.addons.findById('demo.catalogo')!;
      expect(info.updateAvailable, isFalse);
      expect(info.deferredVersion, '1.1.0');

      await tester.tap(find.byTooltip('Verificar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Tudo atualizado'), findsOneWidget);
    });

    testWidgets('incompatível mostra o motivo', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0', platforms: ['android']);
      await harness.openUpdates(tester);

      await tester.tap(find.widgetWithText(FocusableButton, 'Atualizar'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Atualizar'));
      await tester.pumpAndSettle();

      expect(harness.installedVersion, '1.0.0');
      expect(find.text('Esta versão não é compatível com esta plataforma.'),
          findsOneWidget);
    });

    testWidgets('rollback restaura a versão anterior', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.addons.update('demo.catalogo');
      await harness.openUpdates(tester);

      expect(find.text('Voltar para v1.0.0'), findsOneWidget);
      await tester
          .tap(find.widgetWithText(FocusableButton, 'Voltar para v1.0.0'));
      await tester.pumpAndSettle();
      expect(find.text('Voltar à versão anterior?'), findsOneWidget);

      await tester.tap(dialogButton('Voltar versão'));
      await tester.pumpAndSettle();

      expect(harness.installedVersion, '1.0.0');
      expect(find.text('Catálogo Demo voltou para v1.0.0.'),
          findsOneWidget);
    });

    testWidgets('lista marca pendência e atalho abre a tela',
        (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.addons.checkForUpdates();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Atualização disponível'), findsOneWidget);

      await tester.tap(find.byTooltip('Atualizações'));
      await tester.pumpAndSettle();
      expect(find.text('Disponíveis (1)'), findsOneWidget);
    });

    testWidgets('detalhes oferecem ver a atualização', (tester) async {
      final harness = _Harness();
      await harness.install();
      harness.serve(version: '1.1.0');
      await harness.addons.checkForUpdates();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();

      await tester.tap(
          find.widgetWithText(FocusableButton, 'Ver atualização disponível'));
      await tester.pumpAndSettle();
      expect(find.text('Disponíveis (1)'), findsOneWidget);
    });
  });
}
