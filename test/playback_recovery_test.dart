import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/player/player_screen.dart';
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

MediaItem urlItem() => MediaItem(
      id: 'remoto',
      title: 'Video remoto',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/video.mp4',
      addedAt: DateTime(2026, 1, 1),
    );

MediaItem localItem(String path) => MediaItem(
      id: 'local',
      title: 'Video local',
      sourceType: MediaSourceType.local,
      source: path,
      addedAt: DateTime(2026, 1, 1),
    );

/// Motor programavel: emite sessoes sob comando e conta open/stop.
/// O open pode pendurar ou lancar para exercitar o supervisor.
class _ScriptedPlayer implements MediaPlayerService {
  final _controller = StreamController<PlaybackSession>.broadcast();
  PlaybackSession _session = const PlaybackSession();

  int openCount = 0;
  int stopCount = 0;
  Future<void> Function()? openHook;

  void emit(PlaybackSession session) {
    _session = session;
    _controller.add(session);
  }

  void emitStatus(PlaybackStatus status, {String? errorMessage}) =>
      emit(_session.copyWith(
        status: status,
        errorMessage: () => errorMessage,
      ));

  @override
  PlaybackSession get session => _session;

  @override
  Stream<PlaybackSession> get sessionStream => _controller.stream;

  @override
  Widget buildVideoView() => const SizedBox();

  @override
  Future<void> open(MediaItem item) async {
    openCount++;
    if (openHook != null) await openHook!();
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> seekBy(Duration offset) async {}

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> setSpeed(double value) async {}

  @override
  Future<void> selectAudio(String trackId) async {}

  @override
  Future<void> selectSubtitle(String? trackId) async {}

  @override
  Future<void> selectVideo(String? trackId) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> rotateClockwise() async {}

  @override
  Future<void> rotateCounterClockwise() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  group('classifyPlaybackError', () {
    test('tabela de classificacao', () {
      expect(classifyPlaybackError(null), PlaybackErrorKind.unknown);
      expect(classifyPlaybackError(''), PlaybackErrorKind.unknown);
      expect(classifyPlaybackError('Connection timed out'),
          PlaybackErrorKind.timeout);
      expect(classifyPlaybackError('HTTP error 404'), PlaybackErrorKind.source);
      expect(classifyPlaybackError('https: HTTP error 403 Forbidden'),
          PlaybackErrorKind.source);
      expect(classifyPlaybackError('No such file or directory'),
          PlaybackErrorKind.source);
      expect(
          classifyPlaybackError(
              'Failed to open /sdcard/Movies/a.mp4: Permission denied'),
          PlaybackErrorKind.source);
      expect(classifyPlaybackError('Could not resolve host'),
          PlaybackErrorKind.network);
      expect(classifyPlaybackError('Connection refused'),
          PlaybackErrorKind.network);
      expect(classifyPlaybackError('Audio codec missing'),
          PlaybackErrorKind.decoder);
      expect(classifyPlaybackError('Format not supported'),
          PlaybackErrorKind.decoder);
      expect(classifyPlaybackError('kaboom aleatorio'),
          PlaybackErrorKind.unknown);
    });
  });

  group('NoOp stop e erro simulado', () {
    test('stop volta a ociosidade limpa', () async {
      const player = NoOpMediaPlayerService();
      await player.open(urlItem());
      await player.play();
      await player.stop();
      expect(player.session.status, PlaybackStatus.idle);
      expect(player.session.mediaId, isNull);
    });

    test('simulateError força erro classificado', () async {
      const player = NoOpMediaPlayerService();
      player.simulateError(PlaybackErrorKind.decoder);
      expect(player.session.status, PlaybackStatus.error);
      expect(player.session.errorKind, PlaybackErrorKind.decoder);
      await player.stop();
    });
  });

  group('SupervisedPlayerService timeouts', () {
    test('carga travada vira erro de timeout recuperavel', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        expect(player.session.status, PlaybackStatus.loading);

        async.elapse(const Duration(seconds: 29));
        expect(player.session.status, PlaybackStatus.loading);
        async.elapse(const Duration(seconds: 1));
        expect(player.session.status, PlaybackStatus.error);
        expect(player.session.errorKind, PlaybackErrorKind.timeout);

        // Tentar de novo reabre do zero (gera nova geracao).
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        expect(player.session.status, PlaybackStatus.loading);
      });
    });

    test('buffer continuo vira erro de timeout', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.playing);
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.buffering);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 15));
        expect(player.session.status, PlaybackStatus.error);
        expect(player.session.errorKind, PlaybackErrorKind.timeout);
      });
    });

    test('progresso cancela os timers', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));
        inner.emitStatus(PlaybackStatus.playing);
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.buffering);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 14));
        inner.emitStatus(PlaybackStatus.playing);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(player.session.status, PlaybackStatus.playing);
      });
    });

    test('timer de geracao antiga nao dispara apos nova abertura', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));

        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(player.session.status, PlaybackStatus.loading);

        async.elapse(const Duration(seconds: 29));
        expect(player.session.status, PlaybackStatus.error);
      });
    });

    test('sinal de vida apos o timeout recupera sozinho', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(player.session.status, PlaybackStatus.error);

        inner.emitStatus(PlaybackStatus.playing);
        async.flushMicrotasks();
        expect(player.session.status, PlaybackStatus.playing);
      });
    });

    test('stop cancela o timeout pendente', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer();
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        inner.emitStatus(PlaybackStatus.loading);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));
        unawaited(player.stop());
        async.flushMicrotasks();
        expect(player.session.status, PlaybackStatus.idle);

        async.elapse(const Duration(minutes: 5));
        expect(player.session.status, PlaybackStatus.idle);
      });
    });

    test('open futuro pendurado estoura o backstop', () {
      fakeAsync((async) {
        final inner = _ScriptedPlayer()
          ..openHook = () => Completer<void>().future;
        final player = SupervisedPlayerService(
          inner,
          loadTimeout: const Duration(seconds: 30),
          bufferTimeout: const Duration(seconds: 15),
        );
        unawaited(player.open(urlItem()));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(player.session.status, PlaybackStatus.error);
        expect(player.session.errorKind, PlaybackErrorKind.timeout);
      });
    });
  });

  group('SupervisedPlayerService abertura e erros', () {
    test('arquivo ausente falha na pre-checagem sem chamar o motor',
        () async {
      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(localItem(r'C:\nao\existe.mp4'));

      expect(player.session.status, PlaybackStatus.error);
      expect(player.session.errorKind, PlaybackErrorKind.source);
      expect(inner.openCount, 0);
      // ...mas o motor e parado (a midia anterior nao segue tocando).
      expect(inner.stopCount, 1);
    });

    test('arquivo existente passa na pre-checagem', () async {
      final dir = Directory.systemTemp.createTempSync('precheck_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}v.mp4')
        ..writeAsStringSync('x');

      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(localItem(file.path));

      expect(player.session.status, PlaybackStatus.loading);
      expect(inner.openCount, 1);
    });

    test('trocar de midia libera a sessao anterior', () async {
      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(urlItem());
      inner.emitStatus(PlaybackStatus.playing);
      await Future<void>.delayed(Duration.zero);
      await player.open(urlItem());

      expect(inner.stopCount, 2);
      expect(inner.openCount, 2);
      expect(player.session.status, PlaybackStatus.loading);
      expect(player.session.position, Duration.zero);
    });

    test('open nunca lanca: falha do motor vira sessao de erro', () async {
      final inner = _ScriptedPlayer()
        ..openHook = () => throw StateError('codec missing');
      final player = SupervisedPlayerService(inner);
      await player.open(urlItem());

      expect(player.session.status, PlaybackStatus.error);
      expect(player.session.errorKind, PlaybackErrorKind.decoder);
    });

    test('erro nativo e classificado no espelho', () async {
      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(urlItem());
      inner.emitStatus(PlaybackStatus.error,
          errorMessage: 'Could not resolve host exemplo.com');
      await Future<void>.delayed(Duration.zero);

      expect(player.session.status, PlaybackStatus.error);
      expect(player.session.errorKind, PlaybackErrorKind.network);
    });

    test('log tecnico registra etapas sem dados sensiveis', () async {
      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(urlItem());
      inner.emitStatus(PlaybackStatus.error, errorMessage: 'kaboom');
      await Future<void>.delayed(Duration.zero);

      final stages = player.techLog.map((e) => e.stage);
      expect(stages, containsAll(['precheck', 'open', 'error']));
      final dump = player.techLog.join('\n');
      expect(dump.contains('exemplo.com'), isFalse);
      expect(dump.contains('kaboom'), isFalse);
      expect(player.techLog.last.outcome, 'unknown');
      for (final entry in player.techLog) {
        expect(entry.durationMs, isNotNull);
        expect(entry.durationMs!, greaterThanOrEqualTo(0));
      }
    });

    test('log e limitado as entradas mais recentes', () async {
      final inner = _ScriptedPlayer();
      final player = SupervisedPlayerService(inner);
      await player.open(urlItem());
      for (var i = 0; i < 60; i++) {
        inner.emitStatus(PlaybackStatus.error, errorMessage: 'x$i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(player.techLog.length,
          lessThanOrEqualTo(SupervisedPlayerService.maxLogEntries));
    });
  });

  group('player cancelar e erros por tipo', () {
    testWidgets('cancelar durante a carga volta a ociosidade sem sair',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      harness.player.simulateStatus(PlaybackStatus.loading);
      // Sem settle: o progresso indeterminado nunca aquieta. Dois
      // pumps: o evento do stream vira setState no primeiro e
      // renderiza no segundo.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(harness.player.session.status, PlaybackStatus.idle);
    });

    testWidgets('buffering no meio do video nao mostra Cancelar',
        (tester) async {
      // Seek/pausa no meio do video passam por buffering: so o
      // indicador, sem o "Cancelar" da abertura (ele parava o video).
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      await harness.player.seek(const Duration(seconds: 30));
      harness.player.simulateStatus(PlaybackStatus.buffering);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('buffering na abertura ainda oferece Cancelar',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      await harness.player.seek(Duration.zero);
      harness.player.simulateStatus(PlaybackStatus.buffering);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('erro de rede mostra mensagem de conexao', (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      harness.player.simulateError(PlaybackErrorKind.network);
      await tester.pumpAndSettle();
      expect(
          find.text('Não há conexão suficiente para carregar este conteúdo.'),
          findsOneWidget);
    });

    testWidgets('erro de rede em arquivo local não culpa a conexão',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, localItem(r'C:\x.mp4'));

      harness.player.simulateError(PlaybackErrorKind.network);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Este arquivo não está mais disponível no caminho salvo.'),
          findsOneWidget);
    });

    testWidgets('erro de fonte diz de quem e a culpa', (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, localItem(r'C:\x.mp4'));

      harness.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Este arquivo não está mais disponível no caminho salvo.'),
          findsOneWidget);
    });

    testWidgets('erro de decodificador e distinto', (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      harness.player.simulateError(PlaybackErrorKind.decoder);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Não foi possível reproduzir este arquivo neste dispositivo.'),
          findsOneWidget);
    });

    testWidgets('timeout oferece tentar e fechar funcionais', (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      harness.player.simulateError(PlaybackErrorKind.timeout);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'A fonte demorou demais a responder. Tente de novo ou volte.'),
          findsOneWidget);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível reproduzir'), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);

      harness.player.simulateError(PlaybackErrorKind.timeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
    });

    testWidgets('erro sem tipo usa a mensagem padrao', (tester) async {
      final harness = _WidgetHarness();
      await harness.player.stop();
      await harness.pump(tester);
      await harness.openPlayer(tester, urlItem());

      harness.player.simulateStatus(PlaybackStatus.error);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Não foi possível carregar este link. Verifique a conexão ou confirme se o endereço ainda está disponível.'),
          findsOneWidget);
    });
  });
}

class _WidgetHarness {
  _WidgetHarness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        addons = LocalAddonService(InMemoryLocalStore()),
        guard = StartupGuard(InMemoryLocalStore()) {
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

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PlayerApp(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: windows,
      addonService: addons,
      startupGuard: guard,
      diagnosticsService: diagnostics,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openPlayer(WidgetTester tester, MediaItem item) async {
    await library.upsert(item);
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
    await tester.pumpAndSettle();
  }
}
