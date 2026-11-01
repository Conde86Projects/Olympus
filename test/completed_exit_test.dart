import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/focusable_button.dart';

/// Fim do video: "Biblioteca" e "Inicio" salvam a sessao, fecham o
/// player e levam ao destino (celular: troca a aba); "Fechar" volta
/// de onde o usuario veio.
class _Harness {
  _Harness({bool tv = false, this.mobile = false})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false, tvMode: tv));
  }

  final bool mobile;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final LocalAddonService addons;
  final StartupGuard guard;

  Widget get app => PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: NoOpWindowService(),
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

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  /// Abre o player por cima da tela atual e faz o video terminar.
  Future<void> openAndFinish(WidgetTester tester) async {
    final item = MediaItem(
      id: 'fim',
      title: 'Video do fim',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/fim.mp4',
      addedAt: DateTime(2026, 1, 1),
    );
    await library.upsert(item);
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
    await tester.pumpAndSettle();
    player.simulateStatus(PlaybackStatus.completed);
    await tester.pumpAndSettle();
    expect(find.text('Reprodução concluída'), findsOneWidget);
  }
}

Finder _button(String label) => find.widgetWithText(FocusableButton, label);

void main() {
  testWidgets('Biblioteca salva a sessao e abre a Biblioteca (computador)',
      (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await h.openAndFinish(tester);

    await tester.tap(_button('Biblioteca'));
    await tester.pumpAndSettle();

    expect(find.text('Reprodução concluída'), findsNothing);
    expect(find.text('Video do fim'), findsOneWidget);
    expect(find.text('Continuar assistindo'), findsNothing);
    expect(h.history.latestFor('fim'), isNotNull);
    // Voltar da Biblioteca cai no Inicio, nao no player.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reprodução concluída'), findsNothing);
    expect(find.byTooltip('Configurações'), findsOneWidget);
  });

  testWidgets(
      'Biblioteca em tela cheia so sai da tela cheia; o Voltar seguinte '
      'volta de onde veio', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await h.openAndFinish(tester);
    await tester.tap(find.byTooltip('Tela cheia'));
    await tester.pumpAndSettle();

    await tester.tap(_button('Biblioteca'));
    await tester.pumpAndSettle();
    // So saiu da tela cheia: o player segue na tela.
    expect(find.text('Reprodução concluída'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // Voltou de onde veio (o Inicio), nao foi parar na Biblioteca.
    expect(find.text('Reprodução concluída'), findsNothing);
    expect(find.byTooltip('Configurações'), findsOneWidget);
  });

  for (final mobile in [false, true]) {
    testWidgets(
        'Biblioteca escondida no Menu principal some do fim do video '
        '(${mobile ? 'celular' : 'computador'})', (tester) async {
      final h = _Harness(mobile: mobile);
      h.preferences.update(h.preferences.current
          .copyWith(hiddenDestinations: [MainDestination.library]));
      await h.pump(tester);
      await h.openAndFinish(tester);

      expect(_button('Biblioteca'), findsNothing);
      expect(_button('Início'), findsOneWidget);
      expect(_button('Fechar'), findsOneWidget);
    });
  }

  testWidgets('Inicio salva a sessao e volta a tela inicial', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await h.openAndFinish(tester);

    await tester.tap(_button('Início'));
    await tester.pumpAndSettle();

    expect(find.text('Reprodução concluída'), findsNothing);
    expect(h.history.latestFor('fim'), isNotNull);
    expect(find.byTooltip('Configurações'), findsOneWidget);
  });

  testWidgets('Fechar volta ao lugar de onde veio', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.tap(find.byTooltip('Biblioteca'));
    await tester.pumpAndSettle();
    await h.openAndFinish(tester);

    await tester.tap(_button('Fechar'));
    await tester.pumpAndSettle();

    expect(find.text('Reprodução concluída'), findsNothing);
    // Ainda na Biblioteca (a barra do Inicio nao esta na tela).
    expect(find.byTooltip('Configurações'), findsNothing);
  });

  testWidgets('celular: Biblioteca seleciona a aba da Biblioteca',
      (tester) async {
    final h = _Harness(mobile: true);
    await h.pump(tester);
    await h.openAndFinish(tester);

    await tester.tap(_button('Biblioteca'));
    await tester.pumpAndSettle();

    expect(find.text('Reprodução concluída'), findsNothing);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    expect(h.history.latestFor('fim'), isNotNull);
  });

  testWidgets('celular: Inicio seleciona a aba do Inicio', (tester) async {
    final h = _Harness(mobile: true);
    await h.pump(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Favoritos')));
    await tester.pumpAndSettle();
    await h.openAndFinish(tester);

    await tester.tap(_button('Início'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
  });

  testWidgets('TV: foco inicial em Reproduzir novamente e todos alcancaveis',
      (tester) async {
    final h = _Harness(tv: true);
    await h.pump(tester);
    await h.openAndFinish(tester);

    FocusableButton? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<FocusableButton>();
    expect(focused()?.label, 'Reproduzir novamente');

    final seen = <String>{};
    // Linha de cima para a de baixo, depois pela linha de baixo.
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      final b = focused();
      if (b != null) seen.add(b.label);
    }
    expect(seen, containsAll(['Biblioteca', 'Início', 'Fechar']));
    expect(tester.takeException(), isNull);

    await tester.tap(_button('Biblioteca'));
    await tester.pumpAndSettle();
    expect(find.text('Reprodução concluída'), findsNothing);
  });
}
