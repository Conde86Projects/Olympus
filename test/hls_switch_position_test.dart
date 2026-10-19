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

const _at = Duration(seconds: 200);

/// Player com seeks registrados, avanço sem registro (frames) e
/// pouso configurável por tentativa.
class _SeekPlayer extends NoOpMediaPlayerService {
  final opened = <MediaItem>[];
  final seeks = <Duration>[];

  int throwFirstSeeks = 0;
  Duration Function(Duration target, int attempt)? landing;

  @override
  Future<void> open(MediaItem item) async {
    opened.add(item);
    await super.open(item);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    if (seeks.length <= throwFirstSeeks) {
      throw StateError('seek indisponível');
    }
    await super.seek(landing?.call(position, seeks.length) ?? position);
  }

  Future<void> nudge(Duration position) => super.seek(position);
}

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = _SeekPlayer(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences
        .update(preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final _SeekPlayer player;
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

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  Size surface = const Size(960, 540),
  Duration? duration = const Duration(minutes: 10),
  void Function(_SeekPlayer player)? configure,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => HlsVariants.debugFetchOverride = null);
  final harness = _Harness();
  configure?.call(harness.player);
  await harness.preferences
      .update(harness.preferences.current.copyWith(tvMode: true));
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final media = MediaItem(
    id: 'hls',
    title: 'HLS',
    sourceType: MediaSourceType.url,
    source: _masterUrl,
    duration: duration,
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(media);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: media);
  await tester.pumpAndSettle();
  return harness;
}

/// Troca pelo painel e deixa gate (~8 s), verificação (2 s) e
/// validação (1,5 s) acontecerem.
Future<void> _switchTo(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Qualidade'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump(const Duration(seconds: 14));
  await tester.pumpAndSettle();
}

Future<void> _closePanel(WidgetTester tester) async {
  await tester.tap(find.text('Fechar'));
  await tester.pumpAndSettle();
}

void main() {
  group('troca manual preserva a posição', () {
    testWidgets('pouso exato: um seek, item e histórico intactos',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      expect(harness.player.opened.single.source, contains('url_4'));
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');

      expect(harness.player.opened.last.source, contains('url_0'));
      expect(harness.player.opened.last.id, 'hls');
      expect(harness.player.seeks, [_at]);
      expect(harness.player.session.position, _at);
      expect(harness.library.findById('hls')!.source, _masterUrl);

      await _closePanel(tester);
      await tester.tap(find.byTooltip('Fechar').last);
      await tester.pumpAndSettle();
      expect(harness.history.latestFor('hls')!.position, _at);
    });

    // Relato na TCL (19/10): na troca de qualidade o início do vídeo
    // (título) aparecia antes do ponto salvo. A cobertura fica até o
    // vídeo andar a partir do ponto restaurado.
    testWidgets('troca cobre o vídeo até andar do ponto salvo',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      await harness.player.nudge(_at);

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      // Passos curtos até o seek restaurar a posição (sem ultrapassar
      // o teto da cobertura).
      for (var i = 0; i < 60 && harness.player.seeks.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(harness.player.seeks, [_at]);
      expect(find.text('Ajustando a posição…'), findsOneWidget);

      // Andou a partir do ponto salvo: descobre logo depois.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      // Verificação concluída, mas o vídeo não andou: segue coberto
      // (antes descobria aqui e o quadro antigo aparecia).
      expect(find.text('Ajustando a posição…'), findsOneWidget);
      await harness.player.nudge(_at + const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ajustando a posição…'), findsNothing);
      await tester.pump(const Duration(seconds: 14));
      await tester.pumpAndSettle();
    });

    testWidgets('mpv frio (primeiro seek morre): correção recupera',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, configure: (player) {
        player.landing = (target, attempt) =>
            attempt == 1 ? Duration.zero : target;
      });
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');

      expect(harness.player.seeks, [_at, _at]);
      expect(harness.player.session.position, _at);
      expect(harness.player.opened.last.source, contains('url_0'));
    });

    testWidgets('pouso próximo (2 s): nenhuma correção', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, configure: (player) {
        player.landing =
            (target, attempt) => const Duration(seconds: 202);
      });
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');

      expect(harness.player.seeks, [_at]);
      expect(harness.player.session.position,
          const Duration(seconds: 202));
    });

    testWidgets('falha do seek: correção recupera sem erro',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester,
          configure: (player) => player.throwFirstSeeks = 1);
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');

      expect(harness.player.seeks, [_at, _at]);
      expect(harness.player.session.position, _at);
      expect(find.text('Não foi possível reproduzir'), findsNothing);
    });

    testWidgets('sem duração: troca funciona sem correção extra',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness =
          await _openPlayer(tester, duration: null);
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');

      expect(harness.player.opened.last.source, contains('url_0'));
      expect(harness.player.seeks, [_at]);
      expect(harness.player.session.position, _at);
    });
  });

  group('retorno controlado à qualidade anterior', () {
    testWidgets('pouso sempre errado: volta para a anterior',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, configure: (player) {
        // Troca e correção pousam errado; o restore do retorno
        // (3ª tentativa) recupera.
        player.landing = (target, attempt) => attempt >= 3
            ? target
            : const Duration(seconds: 10);
      });
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      expect(harness.player.seeks, [_at, _at, _at]);
      expect(harness.player.opened.last.source, contains('url_4'));
      expect(harness.player.session.position, _at);

      await _closePanel(tester);
      await tester.tap(find.byTooltip('Fechar').last);
      await tester.pumpAndSettle();
      expect(harness.history.latestFor('hls')!.position, _at);
    });

    testWidgets('retorno também falha: pausa e protege o histórico',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, configure: (player) {
        player.landing =
            (target, attempt) => const Duration(seconds: 10);
      });
      await harness.player.play();
      await harness.player.nudge(_at);

      await _switchTo(tester, '720p');
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      // Troca, correção e restore: nada além de 3 seeks.
      expect(harness.player.seeks, [_at, _at, _at]);
      expect(harness.player.opened.last.source, contains('url_4'));
      expect(harness.player.session.status, PlaybackStatus.paused);

      // Saída não grava o ponto errado nem conclui.
      await _closePanel(tester);
      await tester.tap(find.byTooltip('Fechar').last);
      await tester.pumpAndSettle();
      final entry = harness.history.latestFor('hls');
      expect(entry == null || entry.position == _at, isTrue);
      expect(entry?.completed ?? false, isFalse);
      expect(harness.library.findById('hls')!.source, _masterUrl);
    });
  });

  group('downgrade automático preserva a posição', () {
    testWidgets('TV 4K lenta: desce um degrau sem perder o ponto',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final clockStart = DateTime(2026, 1, 1, 12);
      var now = clockStart;
      HlsVariants.debugNowOverride = () => now;
      final harness = await _openPlayer(tester,
          surface: const Size(1920, 1080));
      expect(harness.player.opened.single.source, _masterUrl);
      await harness.player.play();
      await harness.player.nudge(_at);

      // Observador vê lentidão (posição parada no relógio).
      for (var i = 0; i < 16; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      expect(harness.player.opened.last.source, contains('url_0'));
      expect(harness.player.opened.last.id, 'hls');
      expect(harness.player.session.position, _at);
      expect(harness.player.seeks, contains(_at));
    });
  });
}
