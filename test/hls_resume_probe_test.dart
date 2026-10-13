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

class _SeekPlayer extends NoOpMediaPlayerService {
  final opened = <MediaItem>[];
  final seeks = <Duration>[];

  @override
  Future<void> open(MediaItem item) async {
    opened.add(item);
    await super.open(item);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await super.seek(position);
  }
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

void main() {
  testWidgets('sonda resume HLS loga sem mudar seeks nem posição',
      (tester) async {
    HlsVariants.debugFetchOverride = (_) async => _master;
    addTearDown(() => HlsVariants.debugFetchOverride = null);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness();
    await harness.preferences.update(
        harness.preferences.current.copyWith(tvMode: true));
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    final item = MediaItem(
      id: 'hls',
      title: 'HLS',
      sourceType: MediaSourceType.url,
      source: _masterUrl,
      duration: const Duration(minutes: 10),
      lastPosition: _resume,
      addedAt: DateTime(2026, 1, 1),
    );
    await harness.library.upsert(item);
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();

    // Comportamento intacto: seek exato, sem correção.
    expect(harness.inner.seeks, [_resume]);
    expect(harness.player.session.position, _resume);

    // Sonda registrada no log técnico local.
    final log = harness.player.techLog;
    String detailOf(String stage) => log
        .where((e) => e.stage == 'resume-$stage')
        .map((e) => e.outcome ?? '')
        .join(' ');
    expect(detailOf('start'), contains('id=hls'));
    expect(detailOf('start'), contains('targetMs=300000'));
    expect(detailOf('start'), contains('statusBefore='));
    expect(detailOf('seek'), contains('posAfterMs=300000'));
    expect(
      log.where((e) => e.stage == 'resume-reading').length,
      greaterThanOrEqualTo(3),
    );
    expect(
      detailOf('correction'),
      anyOf(contains('skipped'), contains('beforeMs=')),
    );

    // Sem credenciais: nenhum endereço em nenhuma entrada.
    for (final entry in log) {
      expect(entry.outcome ?? '', isNot(contains('http')));
      expect(entry.toString(), isNot(contains('http')));
    }
  });
}
