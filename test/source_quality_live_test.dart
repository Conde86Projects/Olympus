import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/supervised_player_service.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/player_settings_panel.dart';

const liveQualities = [
  SourceQuality(
    id: 'q720',
    label: '720p',
    sourceUrl: 'https://cdn.demo.invalid/v_720.mp4',
  ),
  SourceQuality(
    id: 'q1080',
    label: '1080p',
    sourceUrl: 'https://cdn.demo.invalid/v_1080.mp4',
  ),
];

MediaItem liveItem() => MediaItem(
      id: 'fonte1',
      title: 'Video da fonte',
      sourceType: MediaSourceType.url,
      source: 'https://cdn.demo.invalid/v.mp4',
      duration: const Duration(minutes: 10),
      addedAt: DateTime(2026, 1, 1),
      metadata: {
        'qualities': encodeSourceQualities(liveQualities),
      },
    );

/// Settle sem a fase de semantica: a transicao overlay-de-erro +
/// painel na mesma frame dispara uma corrida de flush de semantica no
/// binding de teste (assert do framework, reproduz sem esta mudanca).
/// Finders de texto/tooltip nao dependem de semantica.
Future<void> _settlePaint(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 16), EnginePhase.paint);
    if (!tester.binding.hasScheduledFrame) return;
  }
}

/// Motor que quebra so na rendicao 720p (a URL padrao abre normal).
class _FailingRenditionPlayer extends NoOpMediaPlayerService {
  @override
  Future<void> open(MediaItem item) async {
    if (item.source.contains('v_720')) {
      throw StateError('rendicao indisponivel');
    }
    await super.open(item);
  }
}

class _Harness {
  _Harness({MediaPlayerService? player})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = player ?? const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences
        .update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final MediaPlayerService player;
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
  group('rotulo Qualidade ao vivo', () {
    testWidgets('ouvinte atualiza a linha sem reabrir o painel',
        (tester) async {
      final selected = ValueNotifier<String?>(null);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSettingsPanel(
              player: const NoOpMediaPlayerService(),
              session: const PlaybackSession(),
              sourceQualities: liveQualities,
              sourceQualityListenable: selected,
              onSelectSourceQuality: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Automática'), findsOneWidget);

      selected.value = 'q720';
      await tester.pump();

      expect(find.text('720p'), findsOneWidget);
      expect(find.text('Automática'), findsNothing);
    });

    testWidgets('sem ouvinte, valor congelado segue igual (compat)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSettingsPanel(
              player: const NoOpMediaPlayerService(),
              session: const PlaybackSession(),
              sourceQualities: liveQualities,
              selectedSourceQualityId: 'q1080',
              onSelectSourceQuality: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1080p'), findsOneWidget);
    });

    testWidgets('tela: trocar rendicao atualiza o dialogo aberto',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await harness.library.upsert(liveItem());
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .pushNamed(AppRoutes.player, arguments: liveItem());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();

      // Dialogo ainda aberto, de volta a principal, com o novo rotulo.
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('Repetir'), findsOneWidget);
    });

    testWidgets('troca com falha mostra erro e mantem dialogo usavel',
        (tester) async {
      final harness = _Harness(
        player: SupervisedPlayerService(_FailingRenditionPlayer()),
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await harness.library.upsert(liveItem());
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .pushNamed(AppRoutes.player, arguments: liveItem());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await _settlePaint(tester);

      // A selecao tentada aparece (e a fonte atual); o painel segue
      // operavel e fecha normal (o overlay de erro tambem tem "Fechar",
      // por isso o escopo).
      expect(find.text('720p'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(PlayerSettingsPanel),
        matching: find.text('Fechar'),
      ));
      await _settlePaint(tester);

      // A falha do motor virou overlay de erro com nova tentativa.
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('escape na subview de qualidade fecha o painel',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await harness.library.upsert(liveItem());
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .pushNamed(AppRoutes.player, arguments: liveItem());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      expect(find.text('Da fonte'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Da fonte'), findsNothing);
      expect(find.text('Repetir'), findsNothing);
    });

    testWidgets('setas + OK selecionam rendicao na subview',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await harness.library.upsert(liveItem());
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .pushNamed(AppRoutes.player, arguments: liveItem());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();

      // Do topo da subview: Voltar -> padrao -> 720p.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('720p'), findsOneWidget);
      expect(find.text('Repetir'), findsOneWidget);
    });
  });
}
