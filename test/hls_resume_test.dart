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

const _resume = Duration(seconds: 300);

/// Player cujo seek pode pousar errado ou falhar, como o demuxer
/// fraco da TCL. Registra todas as tentativas.
class _SeekPlayer extends NoOpMediaPlayerService {
  final opened = <MediaItem>[];
  final seeks = <Duration>[];

  /// Quantas primeiras tentativas lançam erro.
  int throwFirstSeeks = 0;

  /// Onde o seek realmente pousa (tentativa 1-based).
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
    final actual = landing?.call(position, seeks.length) ?? position;
    await super.seek(actual);
  }
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

MediaItem _item({
  String source = _masterUrl,
  Duration? duration = const Duration(minutes: 10),
}) =>
    MediaItem(
      id: 'hls',
      title: 'HLS',
      sourceType: MediaSourceType.url,
      source: source,
      duration: duration,
      lastPosition: _resume,
      addedAt: DateTime(2026, 1, 1),
    );

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  bool tvMode = true,
  MediaItem? item,
  void Function(_SeekPlayer player)? configure,
}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => HlsVariants.debugFetchOverride = null);
  final harness = _Harness();
  configure?.call(harness.player);
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

/// Deixa a verificação de posição (agendada) acontecer.
/// Deixa o gate de prontidão (até ~8 s sem avanço), a verificação
/// (2 s) e a validação do pouso (1,5 s) acontecerem.
Future<void> _driveVerify(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
  await tester.pumpAndSettle();
}

void main() {
  group('tolerância da retomada HLS (unidade)', () {
    test('desvio dentro da tolerância não corrige', () {
      expect(
        HlsVariants.resumeNeedsCorrection(
            const Duration(seconds: 296), _resume),
        isFalse,
      );
      expect(
        HlsVariants.resumeNeedsCorrection(
            const Duration(seconds: 304), _resume),
        isFalse,
      );
    });

    test('undershoot e overshoot além da tolerância corrigem', () {
      expect(
        HlsVariants.resumeNeedsCorrection(
            const Duration(seconds: 240), _resume),
        isTrue,
      );
      expect(
        HlsVariants.resumeNeedsCorrection(
            const Duration(seconds: 350), _resume),
        isTrue,
      );
    });
  });

  group('retomada em master HLS', () {
    testWidgets('undershoot: uma correção e pousa no alvo',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        configure: (player) {
          player.landing = (target, attempt) => attempt == 1
              ? const Duration(seconds: 240)
              : target;
        },
      );
      // Abriu a variante tetada, mesmo id e master na biblioteca.
      expect(harness.player.opened.single.source, contains('url_4'));
      expect(harness.player.opened.single.id, 'hls');
      expect(harness.library.findById('hls')!.source, _masterUrl);

      await _driveVerify(tester);
      expect(harness.player.seeks, [_resume, _resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('overshoot: uma correção e volta ao alvo',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        configure: (player) {
          player.landing = (target, attempt) => attempt == 1
              ? const Duration(seconds: 350)
              : target;
        },
      );
      await _driveVerify(tester);
      expect(harness.player.seeks, [_resume, _resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('correção é no máximo uma, mesmo persistindo o desvio',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        configure: (player) {
          // Seek sempre pousa 60 s antes: a correção não vira loop.
          player.landing =
              (target, attempt) => const Duration(seconds: 240);
        },
      );
      await _driveVerify(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(harness.player.seeks, [_resume, _resume]);
    });

    testWidgets('posição já próxima: nenhuma correção', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        configure: (player) {
          player.landing =
              (target, attempt) => const Duration(seconds: 302);
        },
      );
      await _driveVerify(tester);
      expect(harness.player.seeks, [_resume]);
      expect(harness.player.session.position,
          const Duration(seconds: 302));
    });

    testWidgets('falha do primeiro seek: correção recupera sem erro',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        configure: (player) => player.throwFirstSeeks = 1,
      );
      await _driveVerify(tester);
      expect(harness.player.seeks, [_resume, _resume]);
      expect(harness.player.session.position, _resume);
      expect(find.text('Não foi possível reproduzir'), findsNothing);
      expect(find.byTooltip('Fechar'), findsWidgets);
    });

    testWidgets('master no desktop: abre o master e corrige uma vez',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        tvMode: false,
        configure: (player) {
          player.landing = (target, attempt) => attempt == 1
              ? const Duration(seconds: 240)
              : target;
        },
      );
      expect(harness.player.opened.single.source, _masterUrl);
      await _driveVerify(tester);
      expect(harness.player.seeks, [_resume, _resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('sem duração: retoma sem travar e sem correção extra',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(
        tester,
        item: _item(duration: null),
      );
      // A espera pela duração estoura em silêncio e o seek sai.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await _driveVerify(tester);
      expect(harness.player.opened.single.source, contains('url_4'));
      expect(harness.player.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
      expect(find.text('Não foi possível reproduzir'), findsNothing);
    });
  });

  group('fora do master HLS nada muda', () {
    testWidgets('playlist simples usa o fluxo atual, sem fetch de master',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _media;
      final harness = await _openPlayer(tester);
      expect(harness.player.opened.single.source, _masterUrl);
      await _driveVerify(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(harness.player.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('MP4 não busca variantes nem entra na correção HLS',
        (tester) async {
      var called = false;
      HlsVariants.debugFetchOverride = (_) async {
        called = true;
        return _master;
      };
      final harness = await _openPlayer(
        tester,
        item: _item(source: 'https://midia.test/v.mp4'),
      );
      expect(harness.player.opened.single.source,
          'https://midia.test/v.mp4');
      expect(called, isFalse);
      await _driveVerify(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(harness.player.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
    });

    testWidgets('falha ao detectar o master: fluxo atual, master aberto',
        (tester) async {
      HlsVariants.debugFetchOverride =
          (_) => throw const SocketException('sem rede');
      final harness = await _openPlayer(tester);
      await _driveVerify(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(harness.player.opened.single.source, _masterUrl);
      expect(harness.player.seeks, [_resume]);
      expect(harness.player.session.position, _resume);
    });
  });
}
