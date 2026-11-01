import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

class _Harness {
  _Harness({bool tv = false})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current
        .copyWith(showOnboarding: false, tvMode: tv, tvModeAuto: false));
  }

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

Future<_Harness> _boot(WidgetTester tester,
    {Size size = const Size(1264, 900), bool tv = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final harness = _Harness(tv: tv);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _push(WidgetTester tester, String route) async {
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(route);
  await tester.pumpAndSettle();
}

double _titleHeight(WidgetTester tester) =>
    tester.getSize(find.text('Animações')).height;

void main() {
  group('preferencia', () {
    test('padrao e Normal e o valor sobrevive ao salvar e carregar', () {
      expect(const UserPreferences().textSize, TextSizeOption.normal);
      final loaded = UserPreferences.fromMap(
          const UserPreferences(textSize: TextSizeOption.larger).toMap());
      expect(loaded.textSize, TextSizeOption.larger);
    });

    test('valor salvo desconhecido volta para Normal', () {
      expect(UserPreferences.fromMap({'textSize': 'gigante'}).textSize,
          TextSizeOption.normal);
      expect(UserPreferences.fromMap(const {}).textSize,
          TextSizeOption.normal);
    });

    test('multiplicadores 1,0, 1,15 e 1,3', () {
      expect(TextSizeOption.normal.scale, 1.0);
      expect(TextSizeOption.large.scale, 1.15);
      expect(TextSizeOption.larger.scale, 1.3);
    });
  });

  group('tela de configuracoes', () {
    testWidgets('Aparencia oferece Normal, Grande e Maior; escolha e salva',
        (tester) async {
      final harness = await _boot(tester);
      await _push(tester, AppRoutes.settings);
      expect(find.text('Tamanho do texto'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);

      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      expect(find.text('Grande'), findsWidgets);
      expect(find.text('Maior'), findsWidgets);
      await tester.tap(find.text('Maior').last);
      await tester.pumpAndSettle();

      expect(harness.preferences.current.textSize, TextSizeOption.larger);
    });

    testWidgets('Grande e Maior aumentam o texto mostrado', (tester) async {
      final harness = await _boot(tester);
      await _push(tester, AppRoutes.settings);
      final normal = _titleHeight(tester);

      await harness.preferences.update(
          harness.preferences.current.copyWith(textSize: TextSizeOption.large));
      await tester.pumpAndSettle();
      expect(_titleHeight(tester) / normal, closeTo(1.15, 0.03));

      await harness.preferences.update(harness.preferences.current
          .copyWith(textSize: TextSizeOption.larger));
      await tester.pumpAndSettle();
      expect(_titleHeight(tester) / normal, closeTo(1.3, 0.04));
    });
  });

  group('janelas', () {
    testWidgets('compacta 480x270 com Maior nao estoura', (tester) async {
      final harness = await _boot(tester, size: const Size(464, 231));
      await harness.preferences.update(harness.preferences.current
          .copyWith(textSize: TextSizeOption.larger));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final route in const [
        AppRoutes.library,
        AppRoutes.settings,
        AppRoutes.history,
      ]) {
        await _push(tester, route);
        expect(tester.takeException(), isNull, reason: route);
        Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('na TV o teto da classe de largura continua valendo',
        (tester) async {
      final harness =
          await _boot(tester, size: const Size(960, 540), tv: true);
      await _push(tester, AppRoutes.settings);
      await harness.preferences.update(harness.preferences.current
          .copyWith(textSize: TextSizeOption.larger));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.text('Animações'));
      final tokens =
          TvLayoutTokens.forClass(TvLayout.widthClassOf(context));
      final scaled = MediaQuery.textScalerOf(context).scale(10) / 10;
      expect(scaled, lessThanOrEqualTo(tokens.maxTextScale + 1e-9));
    });
  });
}
