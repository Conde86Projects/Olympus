import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/history_entry.dart';
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

/// Vídeo que ainda não chegou ao ponto salvo: o seek não anda e a posição
/// segue em zero, com a duração já conhecida (visto no celular em 01/11).
class _NotLandedPlayer extends NoOpMediaPlayerService {
  const _NotLandedPlayer();

  @override
  PlaybackSession get session => super.session.copyWith(
        duration: () => const Duration(seconds: 90),
        position: Duration.zero,
      );

  @override
  Future<void> seek(Duration position) async {}
}

/// Vídeo que falhou ao abrir: o motor está em erro e nunca informou posição.
class _FailedPlayer extends NoOpMediaPlayerService {
  const _FailedPlayer();

  @override
  PlaybackSession get session =>
      super.session.copyWith(status: PlaybackStatus.error);
}

/// Tocou um trecho e depois deu erro: o que foi visto continua valendo.
class _FailedAfterPlayingPlayer extends NoOpMediaPlayerService {
  const _FailedAfterPlayingPlayer();

  @override
  PlaybackSession get session => super.session.copyWith(
        status: PlaybackStatus.error,
        duration: () => const Duration(seconds: 90),
      );
}

const _saved = Duration(seconds: 64);

Future<(InMemoryLibraryService, InMemoryHistoryService)> _open(
  WidgetTester tester,
  MediaPlayerService player, {
  bool seeded = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.reset);
  final preferences = InMemoryPreferencesService();
  await preferences.update(preferences.current.copyWith(showOnboarding: false));
  final library = InMemoryLibraryService();
  final history = InMemoryHistoryService();
  final guard = StartupGuard(InMemoryLocalStore());
  final addons = LocalAddonService(InMemoryLocalStore());
  await library.upsert(MediaItem(
    id: 'v',
    title: 'Vídeo',
    duration: const Duration(seconds: 90),
    addedAt: DateTime(2026),
    lastPosition: seeded ? _saved : null,
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.org/v.mp4',
    // Sem histórico, a fileira de Favoritos é que mostra o cartão.
    isFavorite: !seeded,
  ));
  if (seeded) {
    await history.record(HistoryEntry(
      mediaId: 'v',
      accessedAt: DateTime(2026, 1, 2),
      position: _saved,
      percentWatched: 0.7,
    ));
  }
  await tester.pumpWidget(PlayerApp(
    preferencesService: preferences,
    libraryService: library,
    historyService: history,
    playerService: player,
    windowService: NoOpWindowService(),
    addonService: addons,
    startupGuard: guard,
    mobilePlatform: false,
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
  await tester.tap(find.text('Vídeo').first);
  await tester.pumpAndSettle();
  return (library, history);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Fechar'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('player não mostra balão de nome', (tester) async {
    await _open(tester, const NoOpMediaPlayerService());

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byTooltip('Fechar')));
    await tester.pump(const Duration(seconds: 1));
    final close = tester.element(find.byTooltip('Fechar'));
    expect(TooltipTheme.of(close).textStyle?.color?.a, 0);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await _close(tester);
  });

  testWidgets('vídeo que falhou ao abrir não vira visita', (tester) async {
    final (_, history) =
        await _open(tester, const _FailedPlayer(), seeded: false);

    await _close(tester);

    expect(history.latestFor('v'), isNull);
    expect(find.text('Continuar assistindo'), findsNothing);
    expect(find.text('Favoritos'), findsOneWidget);
  });

  testWidgets('estreia sem erro continua registrando a visita',
      (tester) async {
    final (_, history) =
        await _open(tester, const NoOpMediaPlayerService(), seeded: false);

    await _close(tester);

    expect(history.latestFor('v'), isNotNull);
  });

  testWidgets('erro depois de tocar guarda o que foi visto', (tester) async {
    const player = _FailedAfterPlayingPlayer();
    final (_, history) = await _open(tester, player, seeded: false);
    await player.seek(const Duration(seconds: 20));
    await tester.pump();

    await _close(tester);

    expect(history.latestFor('v')?.position, const Duration(seconds: 20));
  });

  testWidgets('sair antes de chegar ao ponto salvo mantém o ponto',
      (tester) async {
    final (library, history) = await _open(tester, const _NotLandedPlayer());

    await _close(tester);

    expect(library.findById('v')!.lastPosition, _saved);
    expect(history.latestFor('v')!.position, _saved);
  });

  testWidgets('voltar ao zero depois de assistir salva o zero',
      (tester) async {
    const player = NoOpMediaPlayerService();
    final (library, history) = await _open(tester, player);
    await player.seek(_saved);
    await tester.pump();
    await player.seek(Duration.zero);
    await tester.pump();

    await _close(tester);

    expect(library.findById('v')!.lastPosition, Duration.zero);
    expect(history.latestFor('v')!.position, Duration.zero);
  });
}
