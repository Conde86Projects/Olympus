import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/models/shortcut_action.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Atalhos de teclado configuraveis, pelo app inteiro.
class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
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

Future<_Harness> _boot(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1264, 900);
  addTearDown(tester.view.reset);
  final harness = _Harness();
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
}

Future<void> _tapRow(WidgetTester tester, String label) async {
  final row = find.widgetWithText(ListTile, label);
  await tester.scrollUntilVisible(row, 200,
      scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _openPlayer(WidgetTester tester, _Harness harness) async {
  final item = MediaItem(
    id: 'atalhos',
    title: 'Vídeo de teste',
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.com/v.mp4',
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
}

void main() {
  group('preferencia', () {
    test('padrao nao guarda nada e usa M, F, I, S, A, C e Q', () {
      const prefs = UserPreferences();
      expect(prefs.shortcuts, isEmpty);
      expect([for (final a in ShortcutAction.values) prefs.keyFor(a)], [
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyQ,
      ]);
    });

    test('a escolha sobrevive a salvar e carregar', () {
      final loaded = UserPreferences.fromMap(const UserPreferences()
          .copyWith(shortcuts: {
        ShortcutAction.mute: LogicalKeyboardKey.keyX,
        ShortcutAction.closePlayer: LogicalKeyboardKey.keyW,
      }).toMap());
      expect(loaded.keyFor(ShortcutAction.mute), LogicalKeyboardKey.keyX);
      expect(loaded.keyFor(ShortcutAction.closePlayer),
          LogicalKeyboardKey.keyW);
      expect(loaded.keyFor(ShortcutAction.fullscreen),
          LogicalKeyboardKey.keyF);
    });

    test('valores desconhecidos, reservados ou em conflito voltam ao padrao',
        () {
      final loaded = UserPreferences.fromMap({
        'shortcuts': {
          'mute': LogicalKeyboardKey.space.keyId,
          'fullscreen': 'F',
          'info': 123456789012,
          'subtitles': LogicalKeyboardKey.keyA.keyId,
          'cinema': LogicalKeyboardKey.keyZ.keyId,
          'inexistente': LogicalKeyboardKey.keyK.keyId,
        },
      });
      expect(loaded.shortcuts, {ShortcutAction.cinema: LogicalKeyboardKey.keyZ});
      expect(UserPreferences.fromMap({'shortcuts': 'x'}).shortcuts, isEmpty);
    });
  });

  group('configuracoes', () {
    testWidgets('mostra a tecla atual de cada acao e as fixas',
        (tester) async {
      await _boot(tester);
      await _openSettings(tester);
      await tester.scrollUntilVisible(find.text('Atalhos'), 200,
          scrollable: find.byType(Scrollable).last);
      for (final a in ShortcutAction.values) {
        final row = find.widgetWithText(ListTile, a.label);
        await tester.scrollUntilVisible(row, 200,
            scrollable: find.byType(Scrollable).last);
        expect(
            find.descendant(
                of: row, matching: find.text(shortcutKeyLabel(a.defaultKey))),
            findsOneWidget,
            reason: a.label);
      }
      expect(find.text('Reproduzir / pausar'), findsOneWidget);
      expect(find.text('Espaço'), findsOneWidget);
    });

    testWidgets('trocar a tecla e restaurar o padrao', (tester) async {
      final harness = await _boot(tester);
      await _openSettings(tester);
      await _tapRow(tester, 'Mudo');
      expect(find.text('Pressione a nova tecla'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.keyX);
      expect(find.text('Pressione a nova tecla'), findsNothing);
      expect(harness.preferences.current.keyFor(ShortcutAction.mute),
          LogicalKeyboardKey.keyX);
      expect(
          find.descendant(
              of: find.widgetWithText(ListTile, 'Mudo'),
              matching: find.text('X')),
          findsOneWidget);

      await _tapRow(tester, 'Restaurar padrão');
      expect(harness.preferences.current.shortcuts, isEmpty);
      expect(
          find.descendant(
              of: find.widgetWithText(ListTile, 'Mudo'),
              matching: find.text('M')),
          findsOneWidget);
    });

    testWidgets('recusa tecla de outra acao dizendo qual', (tester) async {
      final harness = await _boot(tester);
      await _openSettings(tester);
      await _tapRow(tester, 'Mudo');
      await _press(tester, LogicalKeyboardKey.keyF);
      expect(find.text('F já é usada em "Tela cheia".'), findsOneWidget);
      expect(find.text('Pressione a nova tecla'), findsOneWidget);
      expect(harness.preferences.current.shortcuts, isEmpty);
    });

    testWidgets('recusa teclas reservadas', (tester) async {
      final harness = await _boot(tester);
      await _openSettings(tester);
      await _tapRow(tester, 'Mudo');
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.tab,
      ]) {
        await _press(tester, key);
        expect(find.textContaining('é uma tecla reservada'), findsOneWidget,
            reason: key.keyLabel);
        expect(harness.preferences.current.shortcuts, isEmpty);
      }
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Pressione a nova tecla'), findsNothing);
    });
  });

  group('player', () {
    testWidgets('a tecla nova vale e a antiga deixa de valer', (tester) async {
      final harness = await _boot(tester);
      await harness.preferences.update(harness.preferences.current
          .copyWith(shortcuts: {ShortcutAction.info: LogicalKeyboardKey.keyX}));
      await _openPlayer(tester, harness);

      await _press(tester, LogicalKeyboardKey.keyX);
      expect(find.text('Voltar'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Voltar'), findsNothing);
      await _press(tester, LogicalKeyboardKey.keyI);
      expect(find.text('Voltar'), findsNothing);
    });

    testWidgets('sem escolha, as teclas padrao seguem valendo',
        (tester) async {
      final harness = await _boot(tester);
      await _openPlayer(tester, harness);
      await _press(tester, LogicalKeyboardKey.keyI);
      expect(find.text('Voltar'), findsOneWidget);
    });

    testWidgets('a tecla de fechar player fecha o player', (tester) async {
      final harness = await _boot(tester);
      await harness.preferences.update(harness.preferences.current.copyWith(
          shortcuts: {ShortcutAction.closePlayer: LogicalKeyboardKey.keyW}));
      await _openPlayer(tester, harness);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.keyQ);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.keyW);
      expect(find.byTooltip('Fechar'), findsNothing);
    });
  });
}
