import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Formulário "Adicionar repositório" com o controle da TV: setas e OK.
Future<void> _openRepos(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(tester.view.reset);
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);
  final preferences = InMemoryPreferencesService();
  await preferences.update(preferences.current.copyWith(
      showOnboarding: false, tvMode: true, allowUnknownSources: true));
  final library = InMemoryLibraryService();
  final history = InMemoryHistoryService();
  const player = NoOpMediaPlayerService();
  final guard = StartupGuard(InMemoryLocalStore());
  final addons = LocalAddonService(
    InMemoryLocalStore(),
    allowUnknownSources: () => true,
  );
  await tester.pumpWidget(PlayerApp(
    preferencesService: preferences,
    libraryService: library,
    historyService: history,
    playerService: player,
    windowService: NoOpWindowService(),
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
  ));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(Scaffold).first))
      .pushNamed(AppRoutes.addonRepos);
  await tester.pumpAndSettle();
}

bool _editing(WidgetTester tester, int fieldIndex) => tester
    .widget<EditableText>(find.byType(EditableText).at(fieldIndex))
    .focusNode
    .hasFocus;

/// O campo da moldura que está com o foco da TV: 'Nome' ou 'Endereço…'.
String? _frameLabel(WidgetTester tester) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return null;
  for (final label in ['Nome', 'Endereço da listagem']) {
    final inside = find.descendant(
      of: find.byElementPredicate((e) => identical(e, focused)),
      matching: find.text(label),
    );
    if (inside.evaluate().isNotEmpty) return label;
  }
  return null;
}

void main() {
  testWidgets('seta para baixo para em cada campo, sem abrir o teclado',
      (tester) async {
    await _openRepos(tester);

    // Primeiro foco: Voltar. A seguinte entra nos campos, em ordem.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_frameLabel(tester), 'Nome');
    expect(_editing(tester, 0), isFalse, reason: 'teclado só abre com OK');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_frameLabel(tester), 'Endereço da listagem');
    expect(_editing(tester, 1), isFalse);
  });

  testWidgets('OK entra no campo e a seta sai dele', (tester) async {
    await _openRepos(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(_editing(tester, 0), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_editing(tester, 0), isFalse);
    expect(_frameLabel(tester), 'Endereço da listagem');
  });
}
