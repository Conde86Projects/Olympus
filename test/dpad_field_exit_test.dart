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
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/focusable_button.dart';

bool _isFocused(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label))).hasFocus;

bool _fieldFocused(WidgetTester tester) =>
    Focus.of(tester.element(find.byType(EditableText).first)).hasFocus;

Future<void> _pumpRow(
  WidgetTester tester,
  TextEditingController controller, {
  int? maxLines,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          FilledButton(onPressed: () {}, child: const Text('Acima')),
          DpadFieldExit(
            controller: controller,
            child: TextField(controller: controller, maxLines: maxLines),
          ),
          FilledButton(onPressed: () {}, child: const Text('Abaixo')),
        ],
      ),
    ),
  ));
}

/// Monta o app com implementações em memória (mesmo desenho do
/// routes_smoke_test, para o teste integrado do Abrir vídeo).
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
}

void main() {
  group('DpadFieldExit (F4)', () {
    testWidgets('UP sai do campo para o vizinho de cima', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Acima'), isTrue);
      expect(_fieldFocused(tester), isFalse);
    });

    testWidgets('DOWN sai do campo para o vizinho de baixo', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Abaixo'), isTrue);
      expect(_fieldFocused(tester), isFalse);
    });

    testWidgets('LEFT/RIGHT ficam no campo (cursor)', (tester) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);
    });

    testWidgets('multilinha no meio do texto: UP move cursor, não sai',
        (tester) async {
      final controller = TextEditingController(text: 'a\nb\nc');
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller, maxLines: 8);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      controller.selection =
          const TextSelection.collapsed(offset: 2); // linha 'b'
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(_fieldFocused(tester), isTrue);
      expect(_isFocused(tester, 'Acima'), isFalse);
    });

    testWidgets('multilinha na primeira linha: UP sai', (tester) async {
      final controller = TextEditingController(text: 'a\nb\nc');
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller, maxLines: 8);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Acima'), isTrue);
    });

    testWidgets('multilinha na última linha: DOWN sai', (tester) async {
      final controller = TextEditingController(text: 'a\nb\nc');
      addTearDown(controller.dispose);
      await _pumpRow(tester, controller, maxLines: 8);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(_isFocused(tester, 'Abaixo'), isTrue);
    });
  });

  group('Abrir vídeo (F4 integrado)', () {
    testWidgets('foco nasce no Procurar e DOWN atravessa o campo',
        (tester) async {
      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FocusableButton, 'Abrir arquivo'));
      await tester.pumpAndSettle();

      // Foco inicial no primário (sem ele, o D-pad não parte de lugar
      // nenhum nesta tela).
      expect(_isFocused(tester, 'Procurar arquivo…'), isTrue);

      // DOWN entra no campo...
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);

      // ...e DOWN sai do campo para o botão Abrir (o bug: prendia).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_isFocused(tester, 'Abrir arquivo'), isTrue);

      // UP volta para dentro do campo.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_fieldFocused(tester), isTrue);
    });
  });
}
