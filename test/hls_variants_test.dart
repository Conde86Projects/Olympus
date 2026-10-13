import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
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

// Master no formato do x36xhzz: 5 variantes, CODECS com virgula
// entre aspas, URIs relativas.
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
#EXTINF:6.0,
seg_1.ts
''';

class _RecordingPlayer extends NoOpMediaPlayerService {
  _RecordingPlayer();

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
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
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
  bool tvMode = false,
  Size surface = const Size(960, 540),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _Harness();
  if (tvMode) {
    await harness.preferences
        .update(harness.preferences.current.copyWith(tvMode: true));
  }
  addTearDown(() => HlsVariants.debugFetchOverride = null);
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
  group('HlsVariants.parseMaster', () {
    test('le 5 variantes com atributos e URIs relativas', () {
      final variants =
          HlsVariants.parseMaster(_master, Uri.parse(_masterUrl));
      expect(variants, hasLength(5));
      expect(variants.first.height, 720);
      expect(variants.first.bandwidth, 2149280);
      expect(
        variants.first.uri.toString(),
        'https://midia.test/x36xhzz/url_0/193039199_mp4_h264_aac_hd_7.m3u8',
      );
      expect(variants.last.height, 1080);
    });

    test('playlist de midia nao e master', () {
      expect(
        HlsVariants.parseMaster(_media, Uri.parse(_masterUrl)),
        isEmpty,
      );
    });

    test('lixo e vazio dao lista vazia', () {
      final base = Uri.parse(_masterUrl);
      expect(HlsVariants.parseMaster('', base), isEmpty);
      expect(HlsVariants.parseMaster('ola', base), isEmpty);
      expect(
        HlsVariants.parseMaster('#EXTM3U\nseg.ts\n', base),
        isEmpty,
      );
    });

    test('RESOLUTION malformada vira altura nula', () {
      const body = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=abc\n'
          'v.m3u8\n';
      final variants =
          HlsVariants.parseMaster(body, Uri.parse(_masterUrl));
      expect(variants, hasLength(1));
      expect(variants.first.height, isNull);
    });

    test('URI absoluta passa intacta', () {
      const body = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360\n'
          'https://cdn.test/v.m3u8\n';
      final variants =
          HlsVariants.parseMaster(body, Uri.parse(_masterUrl));
      expect(variants.first.uri.toString(), 'https://cdn.test/v.m3u8');
    });
  });

  group('HlsVariants.pickCapped', () {
    List<HlsVariant> variants() =>
        HlsVariants.parseMaster(_master, Uri.parse(_masterUrl));

    HlsVariant? pick(List<HlsVariant> vs) => HlsVariants.pickCapped(
          vs,
          maxHeight: HlsVariants.cappedHeight,
          maxBandwidth: HlsVariants.cappedBandwidth,
        );

    test('padrao pega a 380p30 (480p60 estoura o SoC)', () {
      final selected = pick(variants())!;
      expect(selected.height, 288);
      expect(selected.uri.toString(), contains('url_4'));
    });

    test('teto largo pega a 720', () {
      final selected = HlsVariants.pickCapped(
        variants(),
        maxHeight: 720,
        maxBandwidth: 3000000,
      )!;
      expect(selected.height, 720);
    });

    test('sem resolucao so a banda decide', () {
      const body = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=500000\n'
          'a.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=5000000\n'
          'b.m3u8\n';
      final selected = pick(
          HlsVariants.parseMaster(body, Uri.parse(_masterUrl)))!;
      expect(selected.uri.toString(), contains('a.m3u8'));
    });

    test('nada no teto: a mais leve, nunca o master', () {
      final selected = HlsVariants.pickCapped(
        variants(),
        maxHeight: 100,
        maxBandwidth: 100000,
      )!;
      expect(selected.height, 184);
    });

    test('lista vazia volta nulo', () {
      expect(
        HlsVariants.pickCapped(
          const [],
          maxHeight: HlsVariants.cappedHeight,
          maxBandwidth: HlsVariants.cappedBandwidth,
        ),
        isNull,
      );
    });
  });

  group('HlsVariants.resolve', () {
    test('master resolve para a variante tetada', () async {
      final resolved = await HlsVariants.resolve(
        _masterUrl,
        fetchOverride: (_) async => _master,
      );
      expect(resolved, contains('url_4'));
      expect(resolved, isNot(_masterUrl));
    });

    test('falha de rede cai na URL original', () async {
      final resolved = await HlsVariants.resolve(
        _masterUrl,
        fetchOverride: (_) => throw const SocketException('sem rede'),
      );
      expect(resolved, _masterUrl);
    });

    test('playlist de midia cai na URL original', () async {
      final resolved = await HlsVariants.resolve(
        _masterUrl,
        fetchOverride: (_) async => _media,
      );
      expect(resolved, _masterUrl);
    });

    test('mp4 nem busca: volta a URL intacta', () async {
      var called = false;
      final resolved = await HlsVariants.resolve(
        'https://midia.test/v.mp4',
        fetchOverride: (_) async {
          called = true;
          return _master;
        },
      );
      expect(resolved, 'https://midia.test/v.mp4');
      expect(called, isFalse);
    });
  });

  group('teto por classe na abertura', () {
    testWidgets('TV normal abre a variante 380p', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened, hasLength(1));
      expect(harness.player.opened.single.source, contains('url_4'));
      // O item salvo segue o master (variante expira).
      expect(
        harness.library.findById('hls')!.source,
        _masterUrl,
      );
    });

    testWidgets('desktop abre o master intacto', (tester) async {
      var called = false;
      HlsVariants.debugFetchOverride = (_) async {
        called = true;
        return _master;
      };
      final harness = await _openPlayer(tester);
      expect(harness.player.opened.single.source, _masterUrl);
      expect(called, isFalse);
    });

    testWidgets('TV grande (4K) abre o master intacto', (tester) async {
      var called = false;
      HlsVariants.debugFetchOverride = (_) async {
        called = true;
        return _master;
      };
      final harness = await _openPlayer(
        tester,
        tvMode: true,
        surface: const Size(1920, 1080),
      );
      expect(harness.player.opened.single.source, _masterUrl);
      expect(called, isFalse);
    });

    testWidgets('falha de rede na TV abre o master', (tester) async {
      HlsVariants.debugFetchOverride =
          (_) => throw const SocketException('sem rede');
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened.single.source, _masterUrl);
    });
  });
}
