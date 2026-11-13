import 'package:flutter/material.dart';
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
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Gravacao periodica do ponto de retomada: o relogio salva durante a
/// reproducao, sem o usuario sair do player.
class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
  }

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

  Future<void> openPlayer(WidgetTester tester, MediaItem item) async {
    await library.upsert(item);
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('grava o ponto de retomada durante a reprodução, sem sair',
      (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    final item = MediaItem(
      id: 'filme',
      title: 'Filme longo',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/filme.mp4',
      addedAt: DateTime(2026, 1, 1),
    );
    await harness.openPlayer(tester, item);

    await harness.player.seek(const Duration(minutes: 90));
    await harness.player.play();
    await tester.pump();
    expect(harness.library.findById('filme')!.lastPosition, isNull);

    // Sem sair do player: a gravação vem do relógio.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(harness.library.findById('filme')!.lastPosition,
        const Duration(minutes: 90));
    expect(harness.history.latestFor('filme')!.position,
        const Duration(minutes: 90));
  });

  testWidgets('não grava enquanto pausado', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    final item = MediaItem(
      id: 'pausado',
      title: 'Filme',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/pausado.mp4',
      addedAt: DateTime(2026, 1, 1),
    );
    await harness.openPlayer(tester, item);

    await harness.player.seek(const Duration(minutes: 5));
    await harness.player.pause();
    await tester.pump(const Duration(seconds: 61));

    expect(harness.library.findById('pausado')!.lastPosition, isNull);
  });
}
