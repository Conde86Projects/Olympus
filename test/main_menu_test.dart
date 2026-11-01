import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/home/mobile_shell.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Menu principal: escolher quais destinos aparecem, pelo app inteiro.
class _Harness {
  _Harness({this.mobile = false, bool tv = false})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current
        .copyWith(showOnboarding: false, tvMode: tv, tvModeAuto: false));
  }

  final bool mobile;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final player = const NoOpMediaPlayerService();
  final windows = NoOpWindowService();
  final LocalAddonService addons;
  final StartupGuard guard;

  Widget get app => PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: windows,
        addonService: addons,
        startupGuard: guard,
        mobilePlatform: mobile,
        diagnosticsService: DiagnosticsService(
          store: InMemoryLocalStore(),
          preferences: preferences,
          library: library,
          history: history,
          player: player,
          addons: addons,
          guard: guard,
        ),
      );
}

Future<_Harness> _boot(WidgetTester tester, Size size,
    {bool mobile = false, bool tv = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final harness = _Harness(mobile: mobile, tv: tv);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

Finder _menuSwitch(String label) =>
    find.widgetWithText(SwitchListTile, label);

/// Alterna o interruptor do destino na secao "Menu principal".
Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(_menuSwitch(label), 200,
      scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(_menuSwitch(label));
  await tester.pumpAndSettle();
  await tester.tap(_menuSwitch(label));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  group('preferencia', () {
    test('padrao mostra tudo e a escolha sobrevive a salvar e carregar', () {
      expect(const UserPreferences().hiddenDestinations, isEmpty);
      final loaded = UserPreferences.fromMap(const UserPreferences()
          .copyWith(hiddenDestinations: [
        MainDestination.addons,
        MainDestination.history
      ]).toMap());
      expect(loaded.hiddenDestinations,
          [MainDestination.addons, MainDestination.history]);
    });

    test('valores desconhecidos salvos sao ignorados', () {
      final loaded = UserPreferences.fromMap({
        'hiddenDestinations': [
          'favorites',
          'inicio',
          'settings',
          42,
          'favorites'
        ],
      });
      expect(loaded.hiddenDestinations, [MainDestination.favorites]);
      expect(UserPreferences.fromMap({'hiddenDestinations': 'x'})
          .hiddenDestinations, isEmpty);
    });
  });

  group('configuracoes', () {
    testWidgets('tem interruptor so para os quatro destinos, todos ligados',
        (tester) async {
      await _boot(tester, const Size(1264, 900));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Menu principal'), 200,
          scrollable: find.byType(Scrollable).last);
      for (final label in const [
        'Biblioteca',
        'Favoritos',
        'Add-ons',
        'Histórico'
      ]) {
        await tester.scrollUntilVisible(_menuSwitch(label), 200,
            scrollable: find.byType(Scrollable).last);
        expect(tester.widget<SwitchListTile>(_menuSwitch(label)).value, isTrue,
            reason: label);
      }
      expect(_menuSwitch('Início'), findsNothing);
      expect(_menuSwitch('Configurações'), findsNothing);
    });
  });

  group('computador e TV: barra superior', () {
    for (final tv in const [false, true]) {
      testWidgets('esconder e mostrar de volta (${tv ? 'TV' : 'computador'})',
          (tester) async {
        final harness = await _boot(tester, const Size(1264, 900), tv: tv);
        await tester.tap(find.byTooltip('Configurações'));
        await tester.pumpAndSettle();
        await _toggle(tester, 'Favoritos');
        await _toggle(tester, 'Histórico');
        expect(harness.preferences.current.hiddenDestinations,
            [MainDestination.favorites, MainDestination.history]);

        await _back(tester);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Favoritos'), findsNothing);
        expect(find.byTooltip('Histórico'), findsNothing);
        expect(find.byTooltip('Biblioteca'), findsOneWidget);
        expect(find.byTooltip('Add-ons'), findsOneWidget);
        expect(find.byTooltip('Configurações'), findsOneWidget);

        await tester.tap(find.byTooltip('Configurações'));
        await tester.pumpAndSettle();
        await _toggle(tester, 'Favoritos');
        await _back(tester);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Favoritos'), findsOneWidget);
      });
    }

    testWidgets('a escolha vale ao reabrir o app', (tester) async {
      final harness = await _boot(tester, const Size(1264, 900));
      await harness.preferences.update(harness.preferences.current
          .copyWith(hiddenDestinations: [MainDestination.library]));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Biblioteca'), findsNothing);
      expect(find.byTooltip('Favoritos'), findsOneWidget);
    });

    testWidgets('esconder Add-ons nao desliga nem apaga os instalados',
        (tester) async {
      final harness = await _boot(tester, const Size(1264, 900));
      await harness.addons.install(
          AddonManifest.fromMap(demoManifestJson(id: 'demo.um')),
          originTrusted: false);
      await harness.addons.enable('demo.um');
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await _toggle(tester, 'Add-ons');
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add-ons'), findsNothing);
      expect(harness.addons.addons.single.state, AddonState.active);

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await _toggle(tester, 'Add-ons');
      expect(harness.addons.addons.single.state, AddonState.active);
    });
  });

  group('celular: barra inferior', () {
    const portrait = Size(390, 844);

    testWidgets('esconder um destino nao troca a tela em que o usuario esta',
        (tester) async {
      final harness = await _boot(tester, portrait, mobile: true);
      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      await _toggle(tester, 'Biblioteca');
      await _toggle(tester, 'Favoritos');

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 3);
      expect(
          find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text('Biblioteca')),
          findsNothing);
      // Continua em Ajustes: a aba selecionada e a mesma tela de antes.
      expect((bar.destinations[bar.selectedIndex] as NavigationDestination).label, 'Ajustes');
      expect(find.text('Menu principal'), findsOneWidget);

      await _toggle(tester, 'Biblioteca');
      final back = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(back.destinations.length, 4);
      expect((back.destinations[back.selectedIndex] as NavigationDestination).label, 'Ajustes');
      expect(harness.preferences.current.hiddenDestinations,
          [MainDestination.favorites]);
    });

    testWidgets('esconder o Historico tira o icone do Inicio', (tester) async {
      await _boot(tester, portrait, mobile: true);
      expect(find.byTooltip('Histórico'), findsOneWidget);
      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      await _toggle(tester, 'Histórico');
      await tester.tap(find.text('Início'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Histórico'), findsNothing);
    });

    testWidgets('360 dp sem estouro com toda combinacao', (tester) async {
      final harness = await _boot(tester, const Size(360, 640), mobile: true);
      const all = MainDestination.values;
      for (var mask = 0; mask < 1 << all.length; mask++) {
        await harness.preferences.update(harness.preferences.current.copyWith(
            hiddenDestinations: [
              for (var i = 0; i < all.length; i++)
                if (mask & (1 << i) != 0) all[i]
            ]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'mascara $mask');
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        for (final tab in MobileTab.values) {
          final hidden = tab.hideable != null &&
              harness.preferences.current.hiddenDestinations
                  .contains(tab.hideable);
          expect(
              find.descendant(
                  of: find.byType(NavigationBar),
                  matching: find.text(tab.label)),
              hidden ? findsNothing : findsOneWidget,
              reason: '$mask ${tab.label}');
        }
        expect(bar.selectedIndex, 0);
      }
    });
  });
}
