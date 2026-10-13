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
import 'package:player/services/window_service.dart';
import 'package:player/widgets/player_settings_panel.dart';

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

const _media = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg_0.ts
''';

List<HlsVariant> _variants() =>
    HlsVariants.parseMaster(_master, Uri.parse(_masterUrl));

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

MediaItem _item({
  String id = 'hls',
  String source = _masterUrl,
}) =>
    MediaItem(
      id: id,
      title: 'HLS',
      sourceType: MediaSourceType.url,
      source: source,
      duration: const Duration(minutes: 10),
      addedAt: DateTime(2026, 1, 1),
    );

/// Relogio falso do observador de desempenho.
class _Clock {
  DateTime now = DateTime(2026, 1, 1, 12);
  void advance(Duration d) => now = now.add(d);
}

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  bool tvMode = false,
  Size surface = const Size(960, 540),
  MediaItem? item,
  _Clock? clock,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (clock != null) {
    HlsVariants.debugNowOverride = () => clock.now;
  }
  addTearDown(() => HlsVariants.debugNowOverride = null);
  addTearDown(() => HlsVariants.debugFetchOverride = null);
  final harness = _Harness();
  if (tvMode) {
    await harness.preferences
        .update(harness.preferences.current.copyWith(tvMode: true));
  }
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final media = item ?? _item();
  await harness.library.upsert(media);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: media);
  await tester.pumpAndSettle();
  return harness;
}

/// Janela de observação: baseline num tick, depois avança o
/// relógio e a posição e deixa o próximo tick decidir.
Future<void> _observeWindow(
  WidgetTester tester,
  _Clock clock,
  _RecordingPlayer player, {
  required Duration wall,
  required Duration position,
}) async {
  await player.play();
  await tester.pump(const Duration(seconds: 1)); // baseline
  clock.advance(wall);
  await player.seek(position);
  await tester.pump(const Duration(seconds: 1)); // decisão
  await tester.pumpAndSettle();
}

void main() {
  group('perfil automático (unidade)', () {
    test('TCL/perfil fraco (TV compacta): teto atual preservado', () {
      final d = HlsVariants.autoDecision(
          isTv: true, logicalWidth: 640, platform: 'android');
      expect(d.profile, HlsAutoProfile.weakTv);
      expect(d.capped, isTrue);
      expect(d.maxHeight, HlsVariants.cappedHeight);
      expect(d.maxBandwidth, HlsVariants.cappedBandwidth);
      expect(d.maxHeight, 720);
      expect(d.maxBandwidth, 500000);
    });

    test('TV normal (960): também tetada como hoje', () {
      final d = HlsVariants.autoDecision(
          isTv: true, logicalWidth: 960, platform: 'android');
      expect(d.profile, HlsAutoProfile.tv);
      expect(d.capped, isTrue);
      expect(
        HlsVariants.automaticUrl(_masterUrl, _variants(),
            capped: d.capped,
            maxHeight: d.maxHeight,
            maxBandwidth: d.maxBandwidth),
        contains('url_4'),
      );
    });

    test('TV 4K (1920): sem teto, master', () {
      final d = HlsVariants.autoDecision(
          isTv: true, logicalWidth: 1920, platform: 'android');
      expect(d.profile, HlsAutoProfile.tvBig);
      expect(d.capped, isFalse);
    });

    test('desktop nunca é tetado pelo viewport (janela pequena)', () {
      for (final platform in ['windows', 'android', 'linux']) {
        final d = HlsVariants.autoDecision(
            isTv: false, logicalWidth: 640, platform: platform);
        expect(d.profile, HlsAutoProfile.desktop, reason: platform);
        expect(d.capped, isFalse, reason: platform);
      }
    });

    test('TV sem viewport detectado: fallback seguro é o teto fraco', () {
      final d = HlsVariants.autoDecision(
          isTv: true, logicalWidth: null, platform: 'android');
      expect(d.capped, isTrue);
    });
  });

  group('capacidade observada (unidade)', () {
    test('razão posição/relógio', () {
      expect(
        HlsVariants.playbackRatio(Duration.zero,
            const Duration(seconds: 2), const Duration(seconds: 5)),
        closeTo(0.4, 1e-9),
      );
      expect(
        HlsVariants.playbackRatio(Duration.zero,
            const Duration(seconds: 5), const Duration(seconds: 5)),
        closeTo(1.0, 1e-9),
      );
      expect(
        HlsVariants.playbackRatio(Duration.zero, Duration.zero,
            Duration.zero),
        isNull,
      );
    });

    test('lento no master: desce um degrau (720p)', () {
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: _variants(),
          currentUrl: _masterUrl,
          ratio: 0.4,
        ),
        contains('url_0'),
      );
    });

    test('lento na tetada: desce para a mais leve seguinte', () {
      final capped = HlsVariants.automaticUrl(_masterUrl, _variants(),
          capped: true);
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: _variants(),
          currentUrl: capped,
          ratio: 0.4,
        ),
        contains('url_2'),
      );
    });

    test('saudável, já na mais leve ou sem variantes: não desce', () {
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: _variants(),
          currentUrl: _masterUrl,
          ratio: 0.95,
        ),
        isNull,
      );
      final lightest = _variants()
          .reduce((a, b) =>
              (a.bandwidth ?? 0) < (b.bandwidth ?? 0) ? a : b)
          .uri
          .toString();
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: _variants(),
          currentUrl: lightest,
          ratio: 0.2,
        ),
        isNull,
      );
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: const [],
          currentUrl: _masterUrl,
          ratio: 0.2,
        ),
        isNull,
      );
      expect(
        HlsVariants.downgradeUrl(
          masterUrl: _masterUrl,
          variants: _variants(),
          currentUrl: _masterUrl,
          ratio: null,
        ),
        isNull,
      );
    });
  });

  group('painel: qualidade efetiva visível', () {
    testWidgets('Automática mostra a efetiva no valor e no submenu',
        (tester) async {
      final options = HlsVariants.qualityOptions(_variants(),
          includeOriginal: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSettingsPanel(
              player: const NoOpMediaPlayerService(),
              session: const PlaybackSession(),
              hlsQualities: options,
              selectedHlsQualityId: HlsVariants.autoQualityId,
              onSelectHlsQuality: (_) async {},
              effectiveHlsLabel: '288p',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Automática · 288p'), findsOneWidget);

      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      expect(find.text('Efetiva: 288p'), findsOneWidget);
      expect(find.text('Automática'), findsOneWidget);
    });
  });

  group('player: política automática', () {
    testWidgets('TCL fraca abre tetada e mostra a efetiva',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester,
          tvMode: true, surface: const Size(640, 540));
      expect(harness.player.opened.single.source, contains('url_4'));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Automática · 288p'), findsOneWidget);
    });

    testWidgets('TV normal abre tetada (teto preservado)',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened.single.source, contains('url_4'));
    });

    testWidgets('TV 4K abre master; lento observado desce um degrau',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clock = _Clock();
      final harness = await _openPlayer(tester,
          tvMode: true,
          surface: const Size(1920, 1080),
          clock: clock);
      expect(harness.player.opened.single.source, _masterUrl);

      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 2));
      expect(harness.player.opened.last.source, contains('url_0'));
      expect(harness.player.opened.last.id, 'hls');

      // Efetiva visível e seleção continua Automática.
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Automática · 720p'), findsOneWidget);
    });

    testWidgets('TV 4K saudável não desce', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clock = _Clock();
      final harness = await _openPlayer(tester,
          tvMode: true,
          surface: const Size(1920, 1080),
          clock: clock);
      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 5));
      expect(harness.player.opened, hasLength(1));
    });

    testWidgets('fraca lenta desce para a mais leve seguinte',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clock = _Clock();
      final harness = await _openPlayer(tester,
          tvMode: true, clock: clock);
      expect(harness.player.opened.single.source, contains('url_4'));
      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 2));
      expect(harness.player.opened.last.source, contains('url_2'));
    });

    testWidgets('desktop não é tetado nem rebaixado pelo observador',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clock = _Clock();
      final harness = await _openPlayer(tester, clock: clock);
      expect(harness.player.opened.single.source, _masterUrl);
      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 2));
      expect(harness.player.opened, hasLength(1));
    });

    testWidgets('override manual não é rebaixado pelo observador',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clock = _Clock();
      final harness = await _openPlayer(tester,
          tvMode: true,
          surface: const Size(1920, 1080),
          clock: clock);
      // Manual: 1080p pelo painel.
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, contains('url_8'));
      final count = harness.player.opened.length;
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 2));
      expect(harness.player.opened, hasLength(count));
    });

    testWidgets('fonte sem variantes (playlist simples): master, sem teto',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _media;
      final clock = _Clock();
      final harness = await _openPlayer(tester,
          tvMode: true, clock: clock);
      expect(harness.player.opened.single.source, _masterUrl);
      await _observeWindow(tester, clock, harness.player,
          wall: const Duration(seconds: 5),
          position: const Duration(seconds: 2));
      expect(harness.player.opened, hasLength(1));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
    });

    testWidgets('MP4 na TV: abre intacto, sem fetch nem teto',
        (tester) async {
      var called = false;
      HlsVariants.debugFetchOverride = (_) async {
        called = true;
        return _master;
      };
      final harness = await _openPlayer(
        tester,
        tvMode: true,
        item: _item(id: 'mp4', source: 'https://midia.test/v.mp4'),
      );
      expect(harness.player.opened.single.source,
          'https://midia.test/v.mp4');
      expect(called, isFalse);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
    });

    testWidgets('falha de detecção (fetch): abre o master, fallback seguro',
        (tester) async {
      HlsVariants.debugFetchOverride =
          (_) => throw const SocketException('sem rede');
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened.single.source, _masterUrl);
      // Sem variantes detectadas, nada de qualidade inventada.
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
    });
  });
}
