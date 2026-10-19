import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/sources/owned_test_source.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/features/addons/source_catalog_screen.dart';

class FakeAddonFetcher extends AddonFetcher {
  FakeAddonFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

/// Serviço que falha no catalogo sob demanda (erro isolado com
/// tentar de novo, sem quebrar as demais operacoes).
class FlakyCatalogService extends LocalAddonService {
  FlakyCatalogService(
    super.store, {
    required super.fetcher,
    super.adapters = const [OwnedTestSourceAdapter()],
  });

  bool failCatalog = false;
  bool failResolve = false;

  @override
  Future<List<AddonCatalogItem>> getCatalog(String addonId) {
    if (failCatalog) {
      throw const AddonError.fetchFailed('Falha simulada no catálogo.');
    }
    return super.getCatalog(addonId);
  }

  @override
  Future<MediaItem> resolvePlayback(String addonId, AddonCatalogItem item) {
    if (failResolve) {
      throw const AddonError.unavailable();
    }
    return super.resolvePlayback(addonId, item);
  }
}

const catalogFeedUrl = 'https://owned.invalid/catalogo.json';

String catalogFeed({List<Object?>? catalog}) => jsonEncode({
      'feed': 'player-teste/1',
      'catalog': catalog ??
          [
            {
              'id': 's1',
              'title': 'Item Um',
              'stream': 'https://cdn.opened.invalid/s1.mp4',
              'subtitle': 'Desc Um',
              'duration': 60,
            },
            {'id': 'ruim'},
          ],
      'page': 1,
      'pages': 1,
    });

class _Harness {
  _Harness({Map<String, String>? bodies, LocalAddonService? addons})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = addons ??
            LocalAddonService(
              InMemoryLocalStore(),
              fetcher:
                  FakeAddonFetcher(bodies ?? {catalogFeedUrl: catalogFeed()}),
              adapters: const [OwnedTestSourceAdapter()],
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

  Future<void> openCatalog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fonte Própria (teste)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir catálogo'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('tela de catalogo da fonte (spec 6.1.2)', () {
    testWidgets('abre, lista valido, detalhe rapido reproduz e volta',
        (tester) async {
      final harness = _Harness();
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable('owned.test');
      await harness.pump(tester);
      await harness.openCatalog(tester);

      // Lista: valido aparece, invalido nao.
      expect(find.text('Item Um'), findsOneWidget);
      expect(find.text('Desc Um'), findsOneWidget);
      expect(find.text('ruim'), findsNothing);

      // Detalhe rapido com Reproduzir.
      await tester.tap(find.text('Item Um'));
      await tester.pumpAndSettle();
      expect(find.text('Reproduzir'), findsOneWidget);

      // Reproduzir resolve para a biblioteca e abre o player.
      await tester.tap(find.text('Reproduzir'));
      await tester.pumpAndSettle();
      final saved = harness.library.findById('owned.test:s1');
      expect(saved, isNotNull);
      expect(saved!.source, 'https://cdn.opened.invalid/s1.mp4');
      expect(find.byType(SourceCatalogScreen), findsNothing);

      // Voltar (sistema) retorna ao catalogo.
      Navigator.of(tester.element(find.text('Item Um'))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SourceCatalogScreen), findsOneWidget);
      expect(find.text('Item Um'), findsOneWidget);
    });

    testWidgets('feed vazio informa estado vazio', (tester) async {
      final harness =
          _Harness(bodies: {catalogFeedUrl: catalogFeed(catalog: [])});
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable('owned.test');
      await harness.pump(tester);
      await harness.openCatalog(tester);

      expect(find.text('Esta fonte não possui itens válidos.'), findsOneWidget);
    });

    testWidgets('erro isolado com tentar de novo', (tester) async {
      final bodies = {catalogFeedUrl: catalogFeed()};
      final service = FlakyCatalogService(
        InMemoryLocalStore(),
        fetcher: FakeAddonFetcher(bodies),
      )..failCatalog = true;
      final harness = _Harness(bodies: bodies, addons: service);
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable('owned.test');
      await harness.pump(tester);
      await harness.openCatalog(tester);

      expect(find.text('Falha simulada no catálogo.'), findsOneWidget);
      service.failCatalog = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Item Um'), findsOneWidget);
    });

    testWidgets('foco inicial e seta movem entre itens (D-pad/teclado)',
        (tester) async {
      final harness = _Harness(bodies: {
        catalogFeedUrl: catalogFeed(catalog: [
          {
            'id': 's1',
            'title': 'Item Um',
            'stream': 'https://cdn.opened.invalid/s1.mp4',
          },
          {
            'id': 's2',
            'title': 'Item Dois',
            'stream': 'https://cdn.opened.invalid/s2.mp4',
          },
        ]),
      });
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable('owned.test');
      await harness.pump(tester);
      await harness.openCatalog(tester);

      FocusNode focusOf(String title) =>
          Focus.of(tester.element(find.text(title)));
      expect(focusOf('Item Um').hasFocus, isTrue);
      expect(focusOf('Item Dois').hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusOf('Item Dois').hasFocus, isTrue);
    });

    testWidgets('falha ao resolver mantem catalogo navegavel', (tester) async {
      final bodies = {catalogFeedUrl: catalogFeed()};
      final service = FlakyCatalogService(
        InMemoryLocalStore(),
        fetcher: FakeAddonFetcher(bodies),
      )..failResolve = true;
      final harness = _Harness(bodies: bodies, addons: service);
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable('owned.test');
      await harness.pump(tester);
      await harness.openCatalog(tester);

      await tester.tap(find.text('Item Um'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reproduzir'));
      await tester.pumpAndSettle();

      // Erro controlado na folha, sem travar nem navegar.
      expect(find.text('Fonte indisponível no momento.'), findsOneWidget);
      expect(harness.library.findById('owned.test:s1'), isNull);

      // Dispensar a folha: o catalogo segue navegavel.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Item Um'), findsOneWidget);
    });

    testWidgets('fonte inativa nao abre catalogo', (tester) async {
      final harness = _Harness();
      final preview = await harness.addons.previewSource(catalogFeedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fonte Própria (teste)'));
      await tester.pumpAndSettle();

      expect(find.text('Abrir catálogo'), findsNothing);
      expect(find.text('Ative a fonte para abrir o catálogo.'), findsOneWidget);
    });
  });
}
