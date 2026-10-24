import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/constants/app_constants.dart';
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
import 'package:player/services/system_volume_service.dart';
import 'package:player/services/window_service.dart';

/// Regra de volume por plataforma (decisão de produto 20/10/2026,
/// sem trilho em nenhuma desde o ajuste de layout do Windows):
/// só o mudo dentro do app, em toda parte.
///
/// - Desktop/Windows: volume pelo sistema; volume interno
///   (`initialVolume`) aplicado na abertura e ajustável nas setas
///   com controles ocultos, com persistência; só o mudo no player.
/// - Celular: vale o volume do sistema (botões físicos); o app nunca
///   aplica nem salva volume interno; só o mudo.
/// - TV: vale o volume da TV (VOL+/VOL− do controle remoto, fora do
///   app); o D-pad nunca altera o volume; só o mudo.
///
/// O host de teste relata `TargetPlatform.android`, então cada caso
/// fixa a plataforma-alvo explicitamente (restauração no `finally`,
/// dentro do corpo: a verificação de invariantes roda antes dos
/// `tearDown`).
/// Fake do volume do sistema: o teste controla o estado e emite eventos.
class _FakeSystemVolume extends SystemVolumeService {
  _FakeSystemVolume([SystemVolumeState state = SystemVolumeState.full])
      : _state = state;

  SystemVolumeState _state;
  final _controller = StreamController<SystemVolumeState>.broadcast();

  @override
  Future<SystemVolumeState> current() async => _state;

  @override
  Stream<SystemVolumeState> watch() => _controller.stream;

  void emit(SystemVolumeState state) {
    _state = state;
    _controller.add(state);
  }
}

class _Harness {
  _Harness({this.mobilePlatform = false, this.systemVolume})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
  }

  final bool mobilePlatform;
  final SystemVolumeService? systemVolume;
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
        mobilePlatform: mobilePlatform,
        systemVolumeService:
            systemVolume ?? const NoOpSystemVolumeService(),
        mobileChromeService: SystemMobileChrome(),
      );
}

/// Roda [body] com a plataforma-alvo fixada, restaurando ao final.
Future<void> _withPlatform(
    TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  bool tvMode = false,
  bool mobilePlatform = false,
  double initialVolume = 1.0,
  double playerVolume = 1.0,
  SystemVolumeService? systemVolume,
}) async {
  final harness = _Harness(
      mobilePlatform: mobilePlatform, systemVolume: systemVolume);
  await harness.preferences.update(harness.preferences.current
      .copyWith(tvMode: tvMode, initialVolume: initialVolume));
  await harness.player.setMuted(false);
  await harness.player.setVolume(playerVolume);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: 'vol',
    title: 'Vídeo volume',
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.com/vol.mp4',
    duration: const Duration(minutes: 10),
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _hideControls(WidgetTester tester) async {
  await tester.pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Reproduzir'), findsNothing);
}

void main() {
  group('volume inicial por plataforma', () {
    testWidgets('desktop: abertura aplica o volume inicial', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(
          tester,
          initialVolume: 0.3,
          playerVolume: 1.0,
        );

        expect(harness.player.session.volume, closeTo(0.3, 1e-9));
      });
    });

    testWidgets('TV: abertura ignora o volume inicial (vale o da TV)',
        (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(
          tester,
          tvMode: true,
          initialVolume: 0.3,
          playerVolume: 1.0,
        );

        expect(harness.player.session.volume, closeTo(1.0, 1e-9));
      });
    });

    testWidgets('celular: abertura ignora o volume inicial (vale o do sistema)',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final harness = await _openPlayer(
          tester,
          mobilePlatform: true,
          initialVolume: 0.3,
          playerVolume: 1.0,
        );

        expect(harness.player.session.volume, closeTo(1.0, 1e-9));
      });
    });
  });

  group('setas com controles ocultos', () {
    testWidgets('desktop: cima ajusta o volume e persiste', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(
          tester,
          initialVolume: 0.5,
          playerVolume: 0.5,
        );
        await _hideControls(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(harness.player.session.volume, closeTo(0.55, 1e-9));
        expect(harness.preferences.current.initialVolume, closeTo(0.55, 1e-9));
        expect(find.byTooltip('Pausar'), findsNothing);
        expect(find.byTooltip('Reproduzir'), findsOneWidget);
      });
    });

    testWidgets('TV: cima/baixo só reexibem, sem tocar no volume',
        (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(
          tester,
          tvMode: true,
          initialVolume: 1.0,
          playerVolume: 0.5,
        );
        await _hideControls(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(harness.player.session.volume, closeTo(0.5, 1e-9));
        expect(harness.preferences.current.initialVolume, 1.0);
        expect(find.byTooltip('Reproduzir'), findsOneWidget);

        await _hideControls(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(harness.player.session.volume, closeTo(0.5, 1e-9));
        expect(harness.preferences.current.initialVolume, 1.0);
        expect(find.byTooltip('Reproduzir'), findsOneWidget);
      });
    });

    testWidgets('celular: cima só reexibe, sem tocar no volume',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final harness = await _openPlayer(
          tester,
          mobilePlatform: true,
          initialVolume: 1.0,
          playerVolume: 0.5,
        );
        await _hideControls(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(harness.player.session.volume, closeTo(0.5, 1e-9));
        expect(harness.preferences.current.initialVolume, 1.0);
        expect(find.byTooltip('Reproduzir'), findsOneWidget);
      });
    });

    testWidgets('TV: laterais seguem buscando (progresso)', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(
          tester,
          tvMode: true,
          initialVolume: 1.0,
          playerVolume: 0.5,
        );
        await _hideControls(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(harness.player.session.position, const Duration(seconds: 10));
        expect(harness.player.session.volume, closeTo(0.5, 1e-9));
      });
    });
  });

  group('tecla física de volume despluga o mudo', () {
    testWidgets('TV: VOL+ despluga o mudo sem consumir a tecla',
        (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(tester, tvMode: true);
        await harness.player.setMuted(true);
        await tester.pumpAndSettle();
        expect(harness.player.session.isMuted, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
        await tester.pumpAndSettle();

        expect(harness.player.session.isMuted, isFalse);
      });
    });

    testWidgets('desktop: VOL− despluga o mudo sem consumir a tecla',
        (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(tester);
        await harness.player.setMuted(true);
        await tester.pumpAndSettle();
        expect(harness.player.session.isMuted, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
        await tester.pumpAndSettle();

        expect(harness.player.session.isMuted, isFalse);
      });
    });
  });

  group('volume do sistema no Android', () {
    testWidgets('celular: sistema zerado mostra mudo sem tocar no interno',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final volumes = _FakeSystemVolume(
            const SystemVolumeState(volume: 0.0, muted: false));
        final harness = await _openPlayer(
          tester,
          mobilePlatform: true,
          systemVolume: volumes,
        );

        expect(find.byTooltip('Ativar som'), findsOneWidget);
        expect(harness.player.session.volume, closeTo(1.0, 1e-9));
        expect(harness.player.session.isMuted, isFalse);
      });
    });

    testWidgets('celular: sistema aumentou despluga o mudo do app',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final volumes = _FakeSystemVolume();
        final harness = await _openPlayer(
          tester,
          mobilePlatform: true,
          systemVolume: volumes,
        );
        await harness.player.setMuted(true);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Ativar som'), findsOneWidget);

        volumes.emit(const SystemVolumeState(volume: 0.5, muted: false));
        await tester.pumpAndSettle();

        expect(harness.player.session.isMuted, isFalse);
        expect(find.byTooltip('Silenciar'), findsOneWidget);
      });
    });

    testWidgets('TV: sistema zerado mostra mudo', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final volumes = _FakeSystemVolume(
            const SystemVolumeState(volume: 0.0, muted: false));
        await _openPlayer(
          tester,
          tvMode: true,
          systemVolume: volumes,
        );

        expect(find.byTooltip('Ativar som'), findsOneWidget);
      });
    });
  });

  group('mudo em todas as plataformas (sem trilho em nenhuma)', () {
    testWidgets('desktop: só mudo, sem trilho', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        await _openPlayer(tester);

        expect(find.byTooltip('Silenciar'), findsOneWidget);
        expect(
            tester
                .widgetList<Slider>(find.byType(Slider))
                .where((s) => s.max == 1.0),
            isEmpty);
      });
    });

    testWidgets('TV: mudo alterna sem trilho', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final harness = await _openPlayer(tester, tvMode: true);

        expect(find.byTooltip('Silenciar'), findsOneWidget);
        expect(
            tester
                .widgetList<Slider>(find.byType(Slider))
                .where((s) => s.max == 1.0),
            isEmpty);

        await tester.tap(find.byTooltip('Silenciar'));
        await tester.pumpAndSettle();
        expect(harness.player.session.isMuted, isTrue);
        expect(find.byTooltip('Ativar som'), findsOneWidget);

        await tester.tap(find.byTooltip('Ativar som'));
        await tester.pumpAndSettle();
        expect(harness.player.session.isMuted, isFalse);
        expect(find.byTooltip('Silenciar'), findsOneWidget);
      });
    });

    testWidgets('celular: mudo alterna sem trilho', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final harness = await _openPlayer(tester, mobilePlatform: true);

        expect(find.byTooltip('Silenciar'), findsOneWidget);
        expect(
            tester
                .widgetList<Slider>(find.byType(Slider))
                .where((s) => s.max == 1.0),
            isEmpty);

        await tester.tap(find.byTooltip('Silenciar'));
        await tester.pumpAndSettle();
        expect(harness.player.session.isMuted, isTrue);
        expect(find.byTooltip('Ativar som'), findsOneWidget);
      });
    });
  });
}
