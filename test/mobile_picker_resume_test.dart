import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Seletor do sistema no celular: o app vai a segundo plano e o motor
/// pausa o video (perde a superficie). O play volta sozinho so se
/// estava tocando.
Future<NoOpMediaPlayerService> _openPlayer(
  WidgetTester tester, {
  required bool mobile,
}) async {
  const player = NoOpMediaPlayerService();
  await player.stop();
  final preferences = InMemoryPreferencesService();
  preferences.update(preferences.current.copyWith(showOnboarding: false));
  final library = InMemoryLibraryService();
  final history = InMemoryHistoryService();
  final guard = StartupGuard(InMemoryLocalStore());
  final addons = LocalAddonService(InMemoryLocalStore());
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
    mobilePlatform: mobile,
  ));
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: 'seletor',
    title: 'Vídeo seletor',
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.com/s.mp4',
    duration: const Duration(minutes: 10),
    addedAt: DateTime(2026, 1, 1),
  );
  await library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return player;
}

/// Abre o seletor: o app oculta, o motor pausa; depois o app volta.
Future<void> _seletor(WidgetTester tester, MediaPlayerService player) async {
  final binding = tester.binding;
  addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  await player.pause(); // o motor perde a superficie
  await tester.pump();
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tocando antes do seletor: o play volta sozinho',
      (tester) async {
    final player = await _openPlayer(tester, mobile: true);
    await player.play();
    await tester.pump();
    expect(player.session.status, PlaybackStatus.playing);

    await _seletor(tester, player);

    expect(player.session.status, PlaybackStatus.playing);
  });

  testWidgets('pausado antes do seletor: continua pausado', (tester) async {
    final player = await _openPlayer(tester, mobile: true);
    await player.play();
    await player.pause();
    await tester.pump();

    await _seletor(tester, player);

    expect(player.session.status, PlaybackStatus.paused);
  });

  testWidgets('fora do celular nada muda', (tester) async {
    final player = await _openPlayer(tester, mobile: false);
    await player.play();
    await tester.pump();

    await _seletor(tester, player);

    expect(player.session.status, PlaybackStatus.paused);
  });
}
