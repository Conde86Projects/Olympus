import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/features/settings/language_picker_page.dart';

/// Monta o app com implementacoes em memoria e expoe os servicos para
/// assercao (mesmo desenho do prefs_flows_test).
class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
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
}

/// Superficie alta para as configuracoes caberem sem rolagem.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Foco dentro da página do seletor (a tela de configurações atrás
/// tem os mesmos rótulos — sem escopo o finder pega o elemento errado).
bool _pickerFocused(WidgetTester tester, String label) => Focus.of(
      tester.element(find.descendant(
        of: find.byType(LanguagePickerPage),
        matching: find.text(label),
      )),
    ).hasFocus;

Finder _pickerText(String label) => find.descendant(
      of: find.byType(LanguagePickerPage),
      matching: find.text(label),
    );

/// Abre as configuracoes e toca na linha "Idioma preferido" indicada
/// ([first] = legendas, [last] = áudio).
Future<void> _openPicker(
  WidgetTester tester,
  Finder row,
) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder get _subtitleRow => find
    .widgetWithText(ListTile, 'Idioma preferido')
    .first;
Finder get _audioRow => find
    .widgetWithText(ListTile, 'Idioma preferido')
    .last;

void main() {
  group('seletor de idioma (sem campo de texto)', () {
    testWidgets('linhas de idioma abrem a lista sem TextField',
        (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await _openPicker(tester, _subtitleRow);

      expect(find.text('Idioma das legendas'), findsOneWidget);
      expect(_pickerText('Padrão do sistema'), findsOneWidget);
      expect(_pickerText('português'), findsOneWidget);
      // Guarda estrutural: sem campo para o D-pad prender (o bug da
      // TCL era o foco preso no TextField com o IME comendo as setas).
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('setas atravessam as opções e UP retorna', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await _openPicker(tester, _subtitleRow);

      expect(_pickerFocused(tester, 'Padrão do sistema'), isTrue);

      // Um passo por seta, sem prender: desce para a vizinha...
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_pickerFocused(tester, 'Padrão do sistema'), isFalse);
      expect(_pickerFocused(tester, 'alemão'), isTrue);

      // ...e UP retorna.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_pickerFocused(tester, 'Padrão do sistema'), isTrue);
    });

    testWidgets('OK confirma a legenda e volta com o rótulo',
        (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await _openPicker(tester, _subtitleRow);

      await tester.tap(find.text('português'));
      await tester.pumpAndSettle();

      expect(harness.preferences.current.defaultSubtitle, 'por');
      expect(find.text('Idioma das legendas'), findsNothing);
      expect(find.text('português'), findsWidgets);
    });

    testWidgets('voltar sem escolher preserva a preferência', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await _openPicker(tester, _subtitleRow);

      // Voltar do sistema (o botão da TV): fecha sem alterar.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(harness.preferences.current.defaultSubtitle, isNull);
      expect(find.text('Idioma das legendas'), findsNothing);
    });

    testWidgets('linha do áudio salva o idioma do áudio', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await _openPicker(tester, _audioRow);

      expect(find.text('Idioma do áudio'), findsOneWidget);
      await tester.tap(find.text('inglês'));
      await tester.pumpAndSettle();

      expect(harness.preferences.current.defaultAudio, 'eng');
    });
  });

  group('seletor de idioma no modo TV (TCL)', () {
    testWidgets('setas, OK e voltar pelo D-pad', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.preferences.update(
          harness.preferences.current.copyWith(tvMode: true));
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(_subtitleRow);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.preferences.current.defaultSubtitle, 'deu');

      // Reabre e volta sem tocar: nada muda.
      await tester.tap(_subtitleRow);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.preferences.current.defaultSubtitle, 'deu');
    });
  });
}
