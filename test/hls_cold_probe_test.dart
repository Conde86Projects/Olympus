import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/core/utils/hls_cold_probe.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

const _masterUrl = 'https://midia.test/x36xhzz/x36xhzz.m3u8';

// Master no formato do x36xhzz: 5 variantes, URIs relativas.
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

const _media = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg_0.ts
''';

/// Coletor de log sanitizado: junta etapa + detalhe para inspeção.
class _Logs {
  final entries = <String>[];

  void call(String stage, {String? detail}) =>
      entries.add(detail == null ? stage : '$stage $detail');

  String get joined => entries.join('\n');
}

class _RecordingPlayer extends NoOpMediaPlayerService {
  final opened = <MediaItem>[];

  @override
  Future<void> open(MediaItem item) async {
    opened.add(item);
    await super.open(item);
  }
}

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = _RecordingPlayer(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences
        .update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final _RecordingPlayer player;
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

MediaItem _hlsItem() => MediaItem(
      id: 'hls',
      title: 'HLS',
      sourceType: MediaSourceType.url,
      source: _masterUrl,
      addedAt: DateTime(2026, 1, 1),
    );

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  Size surface = const Size(960, 540),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => HlsVariants.debugFetchOverride = null);
  final harness = _Harness();
  await harness.preferences
      .update(harness.preferences.current.copyWith(tvMode: true));
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = _hlsItem();
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  group('HlsColdProbe.probe (unidade)', () {
    test('rede pronta: uma tentativa, sem retry', () async {
      var calls = 0;
      final logs = _Logs();
      final result = await HlsColdProbe.probe(
        _masterUrl,
        fetchText: (_) async {
          calls++;
          return _master;
        },
        log: logs.call,
      );
      expect(result.outcome, HlsColdOutcome.ready);
      expect(result.variants, hasLength(5));
      expect(result.fetchCount, 1);
      expect(calls, 1);
    });

    test('rede fria com recuperação: falha inicial + retry aquece',
        () async {
      var calls = 0;
      final logs = _Logs();
      final result = await HlsColdProbe.probe(
        _masterUrl,
        fetchText: (_) async {
          calls++;
          if (calls == 1) throw const SocketException('rede fria');
          return _master;
        },
        retryDelay: Duration.zero,
        log: logs.call,
      );
      expect(result.outcome, HlsColdOutcome.recovered);
      expect(result.variants, hasLength(5));
      expect(result.fetchCount, 2);
      expect(calls, 2);
    });

    test('falha permanente: no máximo duas tentativas', () async {
      var calls = 0;
      final logs = _Logs();
      final result = await HlsColdProbe.probe(
        _masterUrl,
        fetchText: (_) async {
          calls++;
          throw const SocketException('sem rede');
        },
        retryDelay: Duration.zero,
        log: logs.call,
      );
      expect(result.outcome, HlsColdOutcome.failed);
      expect(result.variants, isEmpty);
      expect(result.fetchCount, 2);
      expect(calls, 2);
    });

    test('ausência de variantes: playlist simples não inventa nem repete',
        () async {
      var calls = 0;
      final logs = _Logs();
      final result = await HlsColdProbe.probe(
        _masterUrl,
        fetchText: (_) async {
          calls++;
          return _media;
        },
        log: logs.call,
      );
      expect(result.outcome, HlsColdOutcome.empty);
      expect(result.variants, isEmpty);
      expect(result.fetchCount, 1);
      expect(calls, 1);
    });

    test('timeout: tentativa limitada, sem travar', () async {
      var calls = 0;
      final logs = _Logs();
      final hung = Completer<String>();
      addTearDown(() {
        if (!hung.isCompleted) hung.complete('');
      });
      final watch = Stopwatch()..start();
      final result = await HlsColdProbe.probe(
        _masterUrl,
        fetchText: (_) async {
          calls++;
          return hung.future;
        },
        timeout: const Duration(milliseconds: 50),
        retryDelay: Duration.zero,
        log: logs.call,
      );
      watch.stop();
      expect(result.outcome, HlsColdOutcome.failed);
      expect(result.variants, isEmpty);
      expect(result.fetchCount, 2);
      expect(calls, 2);
      // Duas tentativas de 50 ms: folga larga, nunca segundos.
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('logs sanitizados: sem URL, host ou segredo', () async {
      const secretUrl =
          'https://midia.test/x36xhzz/x36xhzz.m3u8?token=SEGREDO123';
      var calls = 0;
      final logs = _Logs();
      final result = await HlsColdProbe.probe(
        secretUrl,
        fetchText: (_) async {
          calls++;
          if (calls == 1) throw const SocketException('rede fria');
          return _master;
        },
        retryDelay: Duration.zero,
        log: logs.call,
      );
      expect(result.outcome, HlsColdOutcome.recovered);
      expect(logs.entries, isNotEmpty);
      expect(logs.joined, isNot(contains('SEGREDO123')));
      expect(logs.joined, isNot(contains('midia.test')));
      expect(logs.joined, isNot(contains('token=')));
      expect(logs.joined, isNot(contains('http')));
      expect(logs.joined, isNot(contains('m3u8')));
    });
  });

  group('player: detecção fria (widget)', () {
    testWidgets('rede fria abre o master de imediato, um único open',
        (tester) async {
      HlsVariants.debugFetchOverride =
          (_) => throw const SocketException('rede fria');
      final harness = await _openPlayer(tester);
      // Fallback seguro: abre o master, sem inventar variante.
      expect(harness.player.opened, hasLength(1));
      expect(harness.player.opened.single.source, _masterUrl);
      expect(harness.player.opened.single.id, 'hls');
      // Item salvo segue o master; nada registrado no histórico.
      expect(harness.library.findById('hls')!.source, _masterUrl);
      expect(harness.history.entries, isEmpty);
    });

    testWidgets(
        'recuperação posterior aquece sem reabrir nem tocar histórico/ID',
        (tester) async {
      var calls = 0;
      HlsVariants.debugFetchOverride = (_) async {
        calls++;
        if (calls == 1) throw const SocketException('rede fria');
        return _master;
      };
      final harness = await _openPlayer(tester);
      expect(harness.player.opened.single.source, _masterUrl);

      // A única tentativa posterior, limitada e em segundo plano.
      await tester.pump(HlsColdProbe.retryDelay + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, 2);
      // Sem troca silenciosa, sem restart: nenhum open novo.
      expect(harness.player.opened, hasLength(1));
      expect(harness.player.opened.single.source, _masterUrl);
      expect(harness.player.opened.single.id, 'hls');
      expect(harness.library.findById('hls')!.source, _masterUrl);
      expect(harness.history.entries, isEmpty);
      // A lista aqueceu: o seletor passa a oferecer qualidade.
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsOneWidget);

      // E para por aí: nenhuma terceira tentativa.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(harness.player.opened, hasLength(1));
    });

    testWidgets('falha permanente: segue no master, sem novas tentativas',
        (tester) async {
      var calls = 0;
      HlsVariants.debugFetchOverride = (_) async {
        calls++;
        throw const SocketException('sem rede');
      };
      final harness = await _openPlayer(tester);
      await tester.pump(HlsColdProbe.retryDelay + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(harness.player.opened, hasLength(1));
      expect(harness.player.opened.single.source, _masterUrl);
      // Inicial + a única posterior: nada além disso.
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(harness.player.opened, hasLength(1));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
    });
  });
}
