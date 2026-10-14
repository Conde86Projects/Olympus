import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/focusable_button.dart';

/// Fase 0.2.0 (1): item concluido (>= 97%) sai do "Continuar
/// assistindo", permanece em biblioteca/historico e reabre do inicio
/// com a acao "Ver de novo". Retomada de nao concluidos intacta.
class _Harness {
  _Harness({bool skipOnboarding = true})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    if (skipOnboarding) {
      preferences.update(
          preferences.current.copyWith(showOnboarding: false));
    }
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

MediaItem _item({
  String id = 'concluido',
  String title = 'Video concluido',
  Duration? lastPosition,
  Duration? duration,
}) =>
    MediaItem(
      id: id,
      title: title,
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/$id.mp4',
      lastPosition: lastPosition,
      duration: duration,
      addedAt: DateTime(2026, 1, 1),
    );

Future<void> _openPlayer(
    WidgetTester tester, _Harness harness, MediaItem item) async {
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
}

Future<void> _record(
  _Harness harness, {
  String mediaId = 'concluido',
  Duration position = const Duration(seconds: 97),
  double percent = 0.97,
  bool completed = true,
}) {
  return harness.history.record(HistoryEntry(
    mediaId: mediaId,
    accessedAt: DateTime(2026, 3, 3),
    position: position,
    percentWatched: percent,
    completed: completed,
  ));
}

void main() {
  group('threshold de conclusao (97%)', () {
    test('abaixo de 97% nao conclui', () {
      expect(AppConstants.isCompletedPosition(percent: 0.969), isFalse);
      expect(
          AppConstants.isCompletedPosition(
            position: const Duration(seconds: 96),
            duration: const Duration(seconds: 100),
          ),
          isFalse);
    });

    test('exatos 97% conclui', () {
      expect(AppConstants.isCompletedPosition(percent: 0.97), isTrue);
      expect(
          AppConstants.isCompletedPosition(
            position: const Duration(seconds: 97),
            duration: const Duration(seconds: 100),
          ),
          isTrue);
    });

    test('acima de 97% conclui', () {
      expect(AppConstants.isCompletedPosition(percent: 0.999), isTrue);
      expect(
          AppConstants.isCompletedPosition(
            position: const Duration(seconds: 310),
            duration: const Duration(seconds: 316),
          ),
          isTrue);
    });

    test('sem dados suficientes nao conclui', () {
      expect(AppConstants.isCompletedPosition(), isFalse);
      expect(
          AppConstants.isCompletedPosition(
              position: const Duration(seconds: 10)),
          isFalse);
      expect(
          AppConstants.isCompletedPosition(
            position: const Duration(seconds: 10),
            duration: Duration.zero,
          ),
          isFalse);
    });

    test('isResumable segue o threshold', () {
      MediaItem at(double seconds) => _item(
          lastPosition: Duration(milliseconds: (seconds * 1000).round()),
          duration: const Duration(seconds: 100));
      expect(at(50).isResumable, isTrue);
      expect(at(96).isResumable, isTrue);
      expect(at(97).isResumable, isFalse);
      expect(at(99).isResumable, isFalse);
      expect(_item().isResumable, isFalse);
    });
  });

  group('concluido fora do Continuar assistindo', () {
    testWidgets('item concluido nao aparece, mas fica em biblioteca e historico',
        (tester) async {
      final harness = _Harness();
      await harness.library.upsert(_item(
        lastPosition: const Duration(seconds: 97),
        duration: const Duration(seconds: 100),
      ));
      await _record(harness);
      await harness.pump(tester);

      expect(find.text('Continuar assistindo'), findsNothing);
      expect(harness.library.findById('concluido'), isNotNull);
      expect(harness.history.latestFor('concluido')?.completed, isTrue);
    });

    testWidgets('percentual alto sem flag tambem sai da lista',
        (tester) async {
      final harness = _Harness();
      await harness.library.upsert(_item(
        lastPosition: const Duration(seconds: 98),
        duration: const Duration(seconds: 100),
      ));
      await _record(harness, percent: 0.98, completed: false);
      await harness.pump(tester);

      expect(find.text('Continuar assistindo'), findsNothing);
      expect(harness.library.findById('concluido'), isNotNull);
    });

    testWidgets('nao concluido continua na lista (regressao)',
        (tester) async {
      final harness = _Harness();
      await harness.library.upsert(_item(
        id: 'metade',
        title: 'Video metade',
        lastPosition: const Duration(minutes: 5),
        duration: const Duration(minutes: 10),
      ));
      await _record(harness,
          mediaId: 'metade',
          position: const Duration(minutes: 5),
          percent: 0.5,
          completed: false);
      await harness.pump(tester);

      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(find.text('Video metade'), findsOneWidget);
    });
  });

  group('reabertura de concluido', () {
    testWidgets('comeca em 0:00 e oferece Ver de novo', (tester) async {
      final harness = _Harness();
      await _record(harness);
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
            lastPosition: const Duration(seconds: 97),
            duration: const Duration(seconds: 100),
          ));

      expect(harness.player.session.position, Duration.zero);
      expect(find.widgetWithText(FocusableButton, 'Ver de novo'),
          findsOneWidget);
    });

    testWidgets('Ver de novo reve do inicio', (tester) async {
      final harness = _Harness();
      await _record(harness);
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
            lastPosition: const Duration(seconds: 97),
            duration: const Duration(seconds: 100),
          ));

      await tester
          .tap(find.widgetWithText(FocusableButton, 'Ver de novo'));
      await tester.pumpAndSettle();

      expect(harness.player.session.position, Duration.zero);
      expect(harness.player.session.status, PlaybackStatus.playing);
      expect(find.widgetWithText(FocusableButton, 'Ver de novo'),
          findsNothing);
    });

    testWidgets('sair sem progresso preserva historico e biblioteca',
        (tester) async {
      final harness = _Harness();
      await _record(harness);
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
            lastPosition: const Duration(seconds: 97),
            duration: const Duration(seconds: 100),
          ));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final entry = harness.history.latestFor('concluido');
      expect(entry?.completed, isTrue);
      expect(entry?.position, const Duration(seconds: 97));
      expect(harness.library.findById('concluido'), isNotNull);
    });

    testWidgets('nao concluido retoma a posicao salva (regressao)',
        (tester) async {
      final harness = _Harness();
      await _record(harness,
          mediaId: 'metade',
          position: const Duration(minutes: 5),
          percent: 0.5,
          completed: false);
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
            id: 'metade',
            title: 'Video metade',
            lastPosition: const Duration(minutes: 5),
            duration: const Duration(minutes: 10),
          ));

      expect(harness.player.session.position, const Duration(minutes: 5));
      expect(find.widgetWithText(FocusableButton, 'Ver de novo'),
          findsNothing);
    });
  });
}
