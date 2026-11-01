import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/player_settings_panel.dart';

/// Ticket 24 (spec 16): na TV o painel de opcoes do player segura o foco.
/// Seta para cima no primeiro item e para baixo no ultimo nao podem levar
/// o foco aos botoes do canto que ficam atras do painel.

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore());

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
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
        mobileChromeService: SystemMobileChrome(),
      );
}

Future<_Harness> _openPlayerTv(WidgetTester tester) async {
  final harness = _Harness();
  await harness.preferences.update(harness.preferences.current
      .copyWith(showOnboarding: false, tvMode: true));
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: 'tv-painel',
    title: 'Vídeo TV',
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.com/tv.mp4',
    duration: const Duration(minutes: 10),
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

bool _focusInPanel() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<PlayerSettingsPanel>() != null;
}

String _where() {
  final context = FocusManager.instance.primaryFocus?.context;
  final tip = context?.findAncestorWidgetOfExactType<Tooltip>()?.message;
  return tip ?? FocusManager.instance.primaryFocus.toString();
}

/// Aperta [key] varias vezes (mais que os itens da subtela) e exige que o
/// foco nunca saia do painel.
Future<void> _holdFocus(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String where,
) async {
  for (var i = 0; i < 14; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
    expect(_focusInPanel(), isTrue,
        reason: '$where: ${key.keyLabel} #${i + 1} levou o foco para '
            '"${_where()}"');
  }
}

Future<void> _checkBothEdges(WidgetTester tester, String where) async {
  expect(_focusInPanel(), isTrue, reason: '$where: foco inicial no painel');
  await _holdFocus(tester, LogicalKeyboardKey.arrowUp, '$where (cima)');
  await _holdFocus(tester, LogicalKeyboardKey.arrowDown, '$where (baixo)');
  await _holdFocus(tester, LogicalKeyboardKey.arrowUp, '$where (cima, 2)');
}

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
  expect(find.text('Velocidade de reprodução'), findsOneWidget);
}

void main() {
  group('TV: painel de opcoes segura o foco', () {
    testWidgets('subtela principal', (tester) async {
      await _openPlayerTv(tester);
      await _openPanel(tester);
      await _checkBothEdges(tester, 'principal');
    });

    for (final title in [
      'Idioma',
      'Legendas',
      'Repetir',
      'Informações do vídeo',
    ]) {
      testWidgets('subtela $title', (tester) async {
        await _openPlayerTv(tester);
        await _openPanel(tester);
        await tester.tap(find.text(title).first);
        await tester.pumpAndSettle();
        await _checkBothEdges(tester, title);
      });
    }

    testWidgets('Legendas aberta pela tecla S', (tester) async {
      await _openPlayerTv(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.text('Abrir arquivo de legenda…'), findsOneWidget);
      await _checkBothEdges(tester, 'Legendas (tecla S)');
    });

    testWidgets('Áudio aberto pela tecla A', (tester) async {
      await _openPlayerTv(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      await _checkBothEdges(tester, 'Áudio (tecla A)');
    });

    testWidgets('Informações abertas pela tecla I', (tester) async {
      await _openPlayerTv(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      await _checkBothEdges(tester, 'Informações (tecla I)');
    });

    testWidgets('Esc fecha o painel e o foco volta ao botão de opções',
        (tester) async {
      await _openPlayerTv(tester);
      await _openPanel(tester);
      await _holdFocus(tester, LogicalKeyboardKey.arrowUp, 'principal');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsNothing);
      expect(_where(), 'Configurações');
    });

    testWidgets('Voltar fecha o painel e o foco volta ao botão de opções',
        (tester) async {
      await _openPlayerTv(tester);
      await _openPanel(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsNothing);
      expect(_where(), 'Configurações');
    });
  });
}
