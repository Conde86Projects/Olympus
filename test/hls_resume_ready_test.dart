import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/core/utils/hls_variants.dart';
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

const _masterUrl = 'https://midia.test/x36xhzz/x36xhzz.m3u8';

const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2149280,CODECS="mp4a.40.2,avc1.64001f",RESOLUTION=1280x720,NAME="720"
url_0/193039199_mp4_h264_aac_hd_7.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=246440,CODECS="mp4a.40.5,avc1.42000d",RESOLUTION=320x184,NAME="240"
url_2/193039199_mp4_h264_aac_ld_7.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=460560,CODECS="mp4a.40.5,avc1.420016",RESOLUTION=512x288,NAME="380"
url_4/193039199_mp4_h264_aac_7.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=836280,CODECS="mp4a.40.2,avc1.64001f",RESOLUTION=848x480,NAME="480"
url_6/193039199_mp4_h264_aac_hq_7.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=6221600,CODECS="mp4a.40.2,avc1.640028",RESOLUTION=1920x1080,NAME="1080"
url_8/193039199_mp4_h264_aac_fhd_7.m3u8
''';

const _resume = Duration(seconds: 300);

/// Player com seeks registrados, avanço de posição sem registro
/// (simula frames do demuxer) e pouso configurável.
class _SeekPlayer extends NoOpMediaPlayerService {
  final opened = <MediaItem>[];
  final seeks = <Duration>[];

  Duration Function(Duration target, int attempt)? landing;

  @override
  Future<void> open(MediaItem item) async {
    opened.add(item);
    await super.open(item);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await super.seek(landing?.call(position, seeks.length) ?? position);
  }

  /// Avanço real de posição sem contar como seek da retomada.
  Future<void> nudge(Duration position) => super.seek(position);
}

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        inner = _SeekPlayer(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    player = SupervisedPlayerService(inner);
    preferences
        .update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final _SeekPlayer inner;
  late final SupervisedPlayerService player;
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

MediaItem _item({String source = _masterUrl}) => MediaItem(
      id: 'hls',
      title: 'HLS',
      sourceType: MediaSourceType.url,
      source: source,
      duration: const Duration(minutes: 10),
      lastPosition: _resume,
      addedAt: DateTime(2026, 1, 1),
    );

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  void Function(_SeekPlayer player)? configure,
}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => HlsVariants.debugFetchOverride = null);
  final harness = _Harness();
  configure?.call(harness.inner);
  await harness.preferences
      .update(harness.preferences.current.copyWith(tvMode: true));
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final media = _item();
  await harness.library.upsert(media);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: media);
  await tester.pumpAndSettle();
  return harness;
}

String _detailOf(SupervisedPlayerService player, String stage) => player
    .techLog
    .where((e) => e.stage == 'resume-$stage')
    .map((e) => e.outcome ?? '')
    .join(' ');

void main() {
  group('prontidão do seek inicial', () {
    testWidgets('seek em buffering espera a saída do buffering',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      harness.inner.simulateStatus(PlaybackStatus.buffering);
      // Sem pumpAndSettle aqui: com o spinner girando ele avança
      // tempo falso sem limite e o gate estouraria.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      // Gate ainda esperando: nenhum seek disparado no frio.
      expect(harness.inner.seeks, isEmpty);

      // Demuxer vivo: sai de buffering e a posição avança
      // (duas amostras distintas após o reset da baseline).
      harness.inner.simulateStatus(PlaybackStatus.playing);
      await harness.inner.nudge(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
      await harness.inner.nudge(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(harness.inner.seeks, [_resume]);
      expect(_detailOf(harness.player, 'readiness'),
          contains('ready=true'));
    });

    testWidgets('primeiro avanço real libera o seek', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(harness.inner.seeks, isEmpty);

      await harness.inner.nudge(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(harness.inner.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('timeout de prontidão: seek sai mesmo assim',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      harness.inner.simulateStatus(PlaybackStatus.buffering);
      // Spinner segue girando: sem pumpAndSettle (nunca estabiliza)
      // e passos de 1 s (saltos grandes num frame só quebram a
      // semântica na transição spinner→overlay de erro).
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.inner.seeks, [_resume]);
      expect(_detailOf(harness.player, 'readiness'),
          contains('ready=false'));
      // Sai de buffering: cancela o bufferTimeout do supervisor
      // antes do teardown (sem construir overlay de erro).
      harness.inner.simulateStatus(PlaybackStatus.ready);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('variante efetiva e fallback', () {
    testWidgets('master por fallback de rede fria corrige uma vez',
        (tester) async {
      var calls = 0;
      HlsVariants.debugFetchOverride = (_) async {
        calls++;
        if (calls == 1) throw const SocketException('rede fria');
        return _master;
      };
      final harness = await _openPlayer(tester, configure: (player) {
        player.landing = (target, attempt) =>
            attempt == 1 ? const Duration(seconds: 240) : target;
      });
      // Abertura caiu no master (detecção falhou no frio)...
      expect(harness.player.session, isNotNull);
      expect(harness.inner.opened.single.source, _masterUrl);

      await harness.inner.nudge(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 14));
      await tester.pumpAndSettle();
      // ...mas a retomada detectou o master e corrigiu uma vez.
      expect(harness.inner.seeks, [_resume, _resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('variante tetada: seek, validação e sem correção extra',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      expect(harness.inner.opened.single.source, contains('url_4'));

      await harness.inner.nudge(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 14));
      await tester.pumpAndSettle();
      expect(harness.inner.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets(
        'overshoot persistente: pausa, protege o histórico e registra',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, configure: (player) {
        player.landing =
            (target, attempt) => const Duration(seconds: 360);
      });
      // Como no aparelho: reprodução em curso (só assim a pausa
      // de segurança do fallback tem efeito observável).
      await harness.player.play();
      await harness.inner.nudge(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 14));
      await tester.pumpAndSettle();

      // Uma correção e nada mais.
      expect(harness.inner.seeks, [_resume, _resume]);
      // Fallback: pausa de segurança e motivo registrado.
      expect(harness.player.session.status, PlaybackStatus.paused);
      expect(_detailOf(harness.player, 'correction-settle'),
          contains('within=false'));
      expect(_detailOf(harness.player, 'fallback'),
          contains('reason=landing-unverified'));

      // Saída não marca concluído nem grava o ponto errado.
      await tester.tap(find.byTooltip('Fechar').first);
      await tester.pumpAndSettle();
      final entry = harness.history.latestFor('hls');
      expect(entry == null || entry.position == _resume, isTrue);
      expect(entry?.completed ?? false, isFalse);
      expect(harness.library.findById('hls')!.lastPosition, _resume);
    });
  });
}
