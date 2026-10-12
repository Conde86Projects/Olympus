import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_install_screen.dart';
import 'package:player/models/addon_info.dart';
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
import 'package:player/core/storage/local_store.dart';

class _FakeFetcher extends AddonFetcher {
  const _FakeFetcher(this.bodies);

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
  _Harness({Map<String, String> bodies = const {}})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          fetcher: _FakeFetcher(bodies),
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

  /// Vai da home ate a tela de instalacao.
  Future<void> openInstall(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Instalar add-on'));
    await tester.pumpAndSettle();
  }
}

String validJson() => jsonEncode(demoManifestJson());

void main() {
  group('tela Instalar add-on', () {
    testWidgets('lista tem entrada para instalar', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      expect(find.text('Instalar add-on'), findsWidgets);
      expect(find.text('Escolha um arquivo de manifesto (.json).'),
          findsOneWidget);
    });

    testWidgets('colar valido mostra revisao e instala desativado',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Colar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), validJson());
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(find.text('Catálogo Demo'), findsOneWidget);
      expect(find.textContaining('catalog.read — Ler catálogos'),
          findsOneWidget);
      expect(find.text('Demonstração sem conteúdo real.'), findsOneWidget);
      expect(
          find.text(
              'Será instalado desativado. Ative nos detalhes após revisar.'),
          findsOneWidget);
      expect(find.textContaining('Fonte desconhecida'), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
      expect(find.text('Inativo'), findsOneWidget);
      expect(find.text('Add-on instalado desativado.'), findsOneWidget);
    });

    testWidgets('colar invalido mostra erro e nao instala', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Colar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '{nao e json');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('O manifesto não é um JSON válido.'), findsOneWidget);
      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('cancelar na revisao aborta sem instalar', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Colar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), validJson());
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(find.text('Cole o conteúdo do manifesto (.json).'),
          findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('link busca, revisa e instala', (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/man.json': validJson(),
      });
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'https://exemplo.com/man.json');
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
    });

    testWidgets('link que falha mostra erro e nao instala', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'https://exemplo.com/x.json');
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível buscar.'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('arquivo com caminho digitado chega a revisao',
        (tester) async {
      // IO sincrono no corpo do teste: testWidgets roda em zona FakeAsync
      // e futures de IO real nunca completariam aqui.
      final dir = Directory.systemTemp.createTempSync('addon_install_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}man.json');
      file.writeAsStringSync(validJson());

      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.enterText(find.byType(TextField), file.path);
      // A leitura da tela e assincrona (sem travar a UI): precisa da
      // zona de async real para o IO completar. pumpAndSettle nao
      // detecta quiescencia dentro de runAsync, entao bombeia quadros
      // com esperas reais (limitado: nunca trava a suite).
      await tester.runAsync(() async {
        await tester.tap(find.text('Ler arquivo'));
        for (var i = 0;
            i < 200 &&
                find.text('Revise antes de instalar').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
    });

    testWidgets('duplicado e rejeitado na confirmacao', (tester) async {
      final harness = _Harness();
      await harness.addons.install(
        await harness.addons.validate(demoManifestJson()),
        originTrusted: false,
      );
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Colar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), validJson());
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(find.text('Este add-on já está instalado.'), findsOneWidget);
      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(harness.addons.addons, hasLength(1));
    });

    testWidgets('args preenchem a aba de link', (tester) async {
      final harness = _Harness();
      final dependencies = AppDependencies(
        preferencesService: harness.preferences,
        libraryService: harness.library,
        historyService: harness.history,
        playerService: harness.player,
        windowService: harness.windows,
        addonService: harness.addons,
        startupGuard: harness.guard,
        diagnosticsService: harness.diagnostics,
      );
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => AddonInstallScreen(dependencies: dependencies),
          settings: const RouteSettings(
            arguments:
                AddonInstallArgs(sourceUrl: 'https://exemplo.com/man.json'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Informe o endereço do manifesto ou do feed JSON (http/https).'),
          findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'https://exemplo.com/man.json');
    });
  });
}
