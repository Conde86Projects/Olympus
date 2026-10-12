import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
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

/// Fake com corpos mutaveis: permite simular recuperacao (falha e
/// depois sucesso na nova tentativa).
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
  _Harness({Map<String, String>? bodies})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          fetcher: _FakeFetcher(bodies ?? {}),
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

  Future<void> openRepos(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Repositórios'));
    await tester.pumpAndSettle();
  }

  Future<void> addRepo(
    WidgetTester tester, {
    required String name,
    required String origin,
    bool trusted = false,
  }) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'Nome'), name);
    await tester.enterText(
        find.widgetWithText(TextField, 'Endereço da listagem'), origin);
    if (trusted) {
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
  }
}

String listingJson() => jsonEncode({
      'addons': [demoManifestJson()],
    });

void main() {
  group('tela Repositórios', () {
    testWidgets('lista tem entrada para repositórios', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      expect(find.text('Adicionar repositório'), findsOneWidget);
      expect(find.text('Nenhum repositório cadastrado'), findsOneWidget);
    });

    testWidgets('adiciona repositório válido e lista', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      expect(find.text('Comunidade'), findsOneWidget);
      expect(find.text('exemplo.com'), findsOneWidget);
      expect(find.text('Não verificado'), findsOneWidget);
      expect(harness.addons.repositories, hasLength(1));
    });

    testWidgets('endereço inválido mostra erro e não cadastra',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Ruim',
        origin: 'não é url',
      );

      expect(find.text('Endereço do repositório inválido (use http/https).'),
          findsOneWidget);
      expect(harness.addons.repositories, isEmpty);
    });

    testWidgets('duplicado é rejeitado', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Um',
        origin: 'https://exemplo.com/repo.json',
      );
      await harness.addRepo(
        tester,
        name: 'Dois',
        origin: 'https://exemplo.com/repo.json',
      );

      expect(find.text('Este endereço já está cadastrado.'),
          findsOneWidget);
      expect(harness.addons.repositories, hasLength(1));
    });

    testWidgets('marca confiável aparece na lista', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Oficial',
        origin: 'https://exemplo.com/oficial.json',
        trusted: true,
      );

      // Titulo do switch do formulario + marca na linha do repositorio.
      expect(find.text('Confiável'), findsNWidgets(2));
      expect(find.text('Não verificado'), findsNothing);
      expect(harness.addons.repositories.single.trusted, isTrue);
    });

    testWidgets('navegar lista itens e instala pelo fluxo de revisão',
        (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
        trusted: true,
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      final installed = harness.addons.findById('demo.catalogo')!;
      expect(installed.originTrusted, isTrue);
      expect(find.text('Instalado'), findsOneWidget);
    });

    testWidgets('cancelar na revisão volta ao repositório', (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Catálogo Demo'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('repositório fora do ar mostra fonte indisponível',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Fora do ar',
        origin: 'https://exemplo.com/off.json',
      );

      await tester.tap(find.text('Fora do ar'));
      await tester.pumpAndSettle();

      expect(find.text('Fonte indisponível no momento.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('nova tentativa recupera após falha', (tester) async {
      final bodies = <String, String>{};
      final harness = _Harness(bodies: bodies);
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Instável',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Instável'));
      await tester.pumpAndSettle();
      expect(find.text('Fonte indisponível no momento.'), findsOneWidget);

      bodies['https://exemplo.com/repo.json'] = listingJson();
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);
    });

    testWidgets('remover pede confirmação e apaga só o cadastro',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Sair',
        origin: 'https://exemplo.com/sair.json',
      );

      await tester.tap(find.byTooltip('Remover repositório'));
      await tester.pumpAndSettle();
      expect(find.text('Remover repositório?'), findsOneWidget);

      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Sair'), findsNothing);
      expect(harness.addons.repositories, isEmpty);
    });

    testWidgets('voltar da navegação retorna à lista', (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar repositório'), findsOneWidget);
      expect(find.text('Catálogo Demo'), findsNothing);
    });
  });
}
