import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/addons/addon_install_screen.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/addon_fetcher.dart';
import 'support/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// T1: botão de fontes desconhecidas. Costuras da Parte 2:
/// serviço ([LocalAddonService] com [InMemoryLocalStore] e fetcher
/// falso), preferência e telas (instalação, repositórios, ajustes).
class _FakeFetcher extends AddonFetcher {
  const _FakeFetcher(this.bodies);

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

String _manifestJson() => jsonEncode(demoManifestJson());

AddonManifest _manifest() =>
    AddonManifest.parseJson(jsonEncode(demoManifestJson()));

AddonManifest _feedManifest(String catalogUrl) =>
    AddonManifest.parseJson(jsonEncode({
      ...demoManifestJson(),
      'catalogUrl': catalogUrl,
    }));

String _feedJson() => jsonEncode({
      'items': [
        {'id': 'v1', 'title': 'Vídeo Um', 'sourceUrl': 'https://cdn.exemplo.com/v1.mp4'},
      ],
    });

String _listingJson() => jsonEncode({
      'addons': [jsonDecode(_manifestJson())],
    });

class _Harness {
  _Harness({Map<String, String> bodies = const {}})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
    addons = LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: _FakeFetcher(bodies),
      allowUnknownSources: () => preferences.current.allowUnknownSources,
    );
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  final StartupGuard guard;
  late final LocalAddonService addons;

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
    await tester.binding.setSurfaceSize(const Size(1080, 3400));
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

  Future<void> openInstall(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar de zip'));
    await tester.pumpAndSettle();
  }

  Future<void> openRepos(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar de repositório'));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
  }

  Future<void> setAllowed(bool value) async {
    await preferences.update(
        preferences.current.copyWith(allowUnknownSources: value));
  }
}

void main() {
  group('preferência de fontes desconhecidas', () {
    test('desligada por padrão', () {
      expect(const UserPreferences().allowUnknownSources, isFalse);
    });

    test('documento antigo carrega desligada', () {
      expect(
          UserPreferences.fromMap(const {}).allowUnknownSources, isFalse);
    });

    test('leitura tolerante: valor estranho cai no desligado', () {
      expect(
          UserPreferences.fromMap(
              const {'allowUnknownSources': 'sim'}).allowUnknownSources,
          isFalse);
    });

    test('liga, salva e volta no mapa', () async {
      final on = const UserPreferences().copyWith(allowUnknownSources: true);
      expect(on.allowUnknownSources, isTrue);
      expect(
          UserPreferences.fromMap(on.toMap()).allowUnknownSources, isTrue);
    });
  });

  group('serviço com o botão desligado', () {
    test('instalar manifesto novo é recusado e nada entra', () async {
      final harness = _Harness();
      await expectLater(
        () => harness.addons.install(_manifest(), originTrusted: false),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      expect(harness.addons.addons, isEmpty);
    });

    test('prévia por link é recusada sem buscar nada', () async {
      final harness = _Harness(
          bodies: {'https://x.exemplo.com/m.json': _manifestJson()});
      await expectLater(
        () => harness.addons.previewSource('https://x.exemplo.com/m.json'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
    });

    test('cadastrar repositório é recusado, confiável ou não', () async {
      final harness = _Harness();
      await expectLater(
        () => harness.addons.addRepository(
            name: 'Novo', originUrl: 'https://n.exemplo.com/l.json'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      await expectLater(
        () => harness.addons.addRepository(
            name: 'Novo', originUrl: 'https://n.exemplo.com/l.json', trusted: true),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      expect(harness.addons.repositories, isEmpty);
    });

    test('repositório não confiável não abre a listagem', () async {
      const listingUrl = 'https://r.exemplo.com/l.json';
      final harness = _Harness(bodies: {listingUrl: _listingJson()});
      await harness.setAllowed(true);
      final repo = await harness.addons.addRepository(
          name: 'Comum', originUrl: listingUrl);
      await harness.setAllowed(false);
      await expectLater(
        () => harness.addons.fetchRepoAddons(repo.id),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
    });

    test('troca para host novo é recusada; mesmo host passa', () async {
      const sameHost = 'https://a.exemplo.com/outro.json';
      const otherHost = 'https://b.exemplo.com/feed.json';
      final harness = _Harness(bodies: {
        'https://a.exemplo.com/feed.json': _feedJson(),
        sameHost: _feedJson(),
      });
      await harness.setAllowed(true);
      await harness.addons.install(
          _feedManifest('https://a.exemplo.com/feed.json'),
          originTrusted: false);
      await harness.setAllowed(false);
      // Sem corpo para o host novo de propósito: a recusa vem antes
      // de qualquer rede.
      await expectLater(
        () => harness.addons.updateSourceUrl('demo.catalogo', otherHost),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.unknown-sources-disabled')),
      );
      final kept = await harness.addons
          .updateSourceUrl('demo.catalogo', sameHost);
      expect(kept.manifest.catalogUrl, sameHost);
      expect(kept.state, AddonState.inactive);
    });

    test('gerenciar o já instalado segue funcionando', () async {
      final harness = _Harness();
      await harness.setAllowed(true);
      await harness.addons.install(_manifest(), originTrusted: false);
      await harness.addons.enable('demo.catalogo');
      await harness.setAllowed(false);
      await harness.addons.disable('demo.catalogo');
      expect(harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
      await harness.addons.enable('demo.catalogo');
      expect(harness.addons.getStatus('demo.catalogo'), AddonState.active);
      expect(await harness.addons.checkForUpdates(), isEmpty);
      await harness.addons.uninstall('demo.catalogo');
      expect(harness.addons.addons, isEmpty);
    });
  });

  group('serviço com o botão ligado', () {
    test('instalar manifesto novo entra desativado', () async {
      final harness = _Harness();
      await harness.setAllowed(true);
      final info = await harness.addons
          .install(_manifest(), originTrusted: false);
      expect(info.state, AddonState.inactive);
    });

    test('marcar repositório como confiável exige o botão ligado',
        () async {
      final harness = _Harness();
      await harness.setAllowed(true);
      final repo = await harness.addons.addRepository(
          name: 'Seguro',
          originUrl: 'https://s.exemplo.com/l.json',
          trusted: true);
      expect(repo.trusted, isTrue);
    });

    test('repositório já confiável instala com o botão desligado',
        () async {
      const listingUrl = 'https://s.exemplo.com/l.json';
      final harness = _Harness(bodies: {listingUrl: _listingJson()});
      await harness.setAllowed(true);
      final repo = await harness.addons.addRepository(
          name: 'Seguro', originUrl: listingUrl, trusted: true);
      final listing = await harness.addons.fetchRepoAddons(repo.id);
      await harness.setAllowed(false);
      // Confiável segue legível com o botão desligado.
      final again = await harness.addons.fetchRepoAddons(repo.id);
      expect(again.single.id, listing.single.id);
      final info = await harness.addons
          .install(again.single, originTrusted: repo.trusted);
      expect(info.state, AddonState.inactive);
    });
  });

  group('telas com o botão desligado', () {
    testWidgets('ajustes mostram o botão e o aviso foca o Cancelar',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openSettings(tester);
      await tester.ensureVisible(
          find.text('Permitir fontes desconhecidas'));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(
          SwitchListTile, 'Permitir fontes desconhecidas'));
      expect(tile.value, isFalse);

      await tester.tap(find.text('Permitir fontes desconhecidas'));
      await tester.pumpAndSettle();
      expect(find.text('Permitir fontes desconhecidas?'), findsOneWidget);
      expect(find.textContaining('O Olympus não verifica essas fontes'),
          findsOneWidget);
      // D-pad: Enter imediato cai no Cancelar focado.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Permitir fontes desconhecidas?'), findsNothing);
      expect(harness.preferences.current.allowUnknownSources, isFalse);
    });

    testWidgets('confirmar o aviso liga o botão', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openSettings(tester);
      await tester.ensureVisible(
          find.text('Permitir fontes desconhecidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permitir fontes desconhecidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.allowUnknownSources, isTrue);
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(
          SwitchListTile, 'Permitir fontes desconhecidas'));
      expect(tile.value, isTrue);
    });

    testWidgets('instalação bloqueia a entrada e o atalho libera',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openInstall(tester);
      expect(find.textContaining('Fontes desconhecidas estão desligadas'),
          findsOneWidget);
      expect(find.text('Ativar fontes desconhecidas'), findsOneWidget);
      expect(find.text('Procurar arquivo…'), findsNothing);

      await tester.tap(find.text('Ativar fontes desconhecidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.allowUnknownSources, isTrue);
      expect(find.text('Procurar pacote…'), findsOneWidget);
    });

    testWidgets('revisão de origem confiável instala com o botão desligado',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      final context = tester.element(find.byTooltip('Add-ons'));
      Navigator.of(context).pushNamed(
        AppRoutes.addonInstall,
        arguments:
            AddonInstallArgs(manifest: _manifest(), originTrusted: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(
          harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
      expect(find.text('Add-on instalado desativado.'), findsOneWidget);
    });

    testWidgets('revisão bloqueada mostra motivo e atalho', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      final context = tester.element(find.byTooltip('Add-ons'));
      Navigator.of(context).pushNamed(
        AppRoutes.addonInstall,
        arguments:
            AddonInstallArgs(manifest: _manifest(), originTrusted: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fontes desconhecidas estão desligadas'),
          findsOneWidget);
      expect(find.text('Ativar fontes desconhecidas'), findsOneWidget);
    });

    testWidgets('repositórios bloqueiam o cadastro e liberam pelo atalho',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);
      expect(find.textContaining('Fontes desconhecidas estão desligadas'),
          findsOneWidget);
      expect(find.text('Ativar fontes desconhecidas'), findsOneWidget);
      expect(find.text('Adicionar'), findsNothing);

      await tester.tap(find.text('Ativar fontes desconhecidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar'), findsOneWidget);
    });

    testWidgets('repositório não confiável mostra motivo e atalho',
        (tester) async {
      const listingUrl = 'https://r.exemplo.com/l.json';
      final harness = _Harness(bodies: {listingUrl: _listingJson()});
      await harness.setAllowed(true);
      await harness.addons
          .addRepository(name: 'Comum', originUrl: listingUrl);
      await harness.setAllowed(false);
      await harness.pump(tester);
      await harness.openRepos(tester);
      await tester.tap(find.text('Comum'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fontes desconhecidas estão desligadas'),
          findsOneWidget);
      expect(find.text('Ativar fontes desconhecidas'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);

      await tester.tap(find.text('Ativar fontes desconhecidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);
    });
  });
}
