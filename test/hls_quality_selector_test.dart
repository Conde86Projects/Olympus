import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:player/widgets/player_controls.dart';
import 'package:player/widgets/player_panel_options.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/tv_player_controls.dart';

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
  String? failOnContains;

  @override
  Future<void> open(MediaItem item) async {
    opened.add(item);
    await super.open(item);
    if (failOnContains != null && item.source.contains(failOnContains!)) {
      simulateError(PlaybackErrorKind.source, 'variant failed');
    }
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
      duration: const Duration(minutes: 10),
      addedAt: DateTime(2026, 1, 1),
    );

MediaItem _mp4Item() => MediaItem(
      id: 'bbb',
      title: 'Big Buck Bunny',
      sourceType: MediaSourceType.url,
      source:
          'https://conde86projects.github.io/olympus-catalog/media/big-buck-bunny.mp4',
      duration: const Duration(minutes: 9, seconds: 56),
      addedAt: DateTime(2026, 1, 1),
    );


Future<_Harness> _openPlayer(
  WidgetTester tester, {
  bool tvMode = false,
  Size surface = const Size(960, 540),
  MediaItem? item,
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
  item ??= _hlsItem();
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

/// Painel isolado com selecao viva (como a tela do player faz via
/// listenable): escolher atualiza o grupo para a proxima escolha.
class _HlsPanelHarness extends StatefulWidget {
  const _HlsPanelHarness({
    required this.options,
    required this.initialSelected,
    required this.chosen,
  });

  final List<HlsQualityOption> options;
  final String initialSelected;
  final List<String> chosen;

  @override
  State<_HlsPanelHarness> createState() => _HlsPanelHarnessState();
}

class _HlsPanelHarnessState extends State<_HlsPanelHarness> {
  late String _selected = widget.initialSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerSettingsPanel(
          player: const NoOpMediaPlayerService(),
          session: const PlaybackSession(),
          hls: HlsOptions(
            qualities: widget.options,
            selectedId: _selected,
            onSelect: (id) async {
              widget.chosen.add(id);
              setState(() => _selected = id);
            },
          ),
          initialView: PlayerPanelView.quality,
        ),
      ),
    );
  }
}

Future<void> _openQualityViaPanel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
  expect(find.text('Qualidade'), findsOneWidget);
  await tester.tap(find.text('Qualidade'));
  await tester.pumpAndSettle();
}

/// Painel ja aberto de volta na lista principal apos uma escolha:
/// so reentrar em Qualidade (Configuracoes esta atras do dialogo).
Future<void> _reopenQualityFromMainPanel(WidgetTester tester) async {
  expect(find.text('Qualidade'), findsOneWidget);
  await tester.tap(find.text('Qualidade'));
  await tester.pumpAndSettle();
}

void main() {
  group('HlsVariants qualidade manual (unidade)', () {
    test('Automática é o padrão e respeita o teto atual', () {
      expect(HlsVariants.autoQualityId, 'auto');
      final auto = HlsVariants.automaticUrl(_masterUrl, _variants(),
          capped: true);
      // Teto inalterado: 720p/500 kbps -> variante url_4 (288p).
      expect(auto, contains('url_4'));
      expect(HlsVariants.cappedHeight, 720);
      expect(HlsVariants.cappedBandwidth, 500000);
    });

    test('Automática sem teto (desktop/TV grande) é o master', () {
      expect(
        HlsVariants.automaticUrl(_masterUrl, _variants(), capped: false),
        _masterUrl,
      );
    });

    test('opções listam apenas variantes realmente disponíveis', () {
      final options = HlsVariants.qualityOptions(_variants(),
          includeOriginal: true);
      // Automática + Original + 5 variantes do master.
      expect(options, hasLength(7));
      expect(options.first.id, HlsVariants.autoQualityId);
      expect(options[1].id, HlsVariants.originalQualityId);
      expect(options[1].label, 'Original');
      final labels = options.map((o) => o.label).toList();
      expect(labels, containsAll(['1080p', '720p', '480p', '288p', '184p']));
      // Ordenadas da maior para a menor.
      expect(labels.indexOf('1080p'), lessThan(labels.indexOf('720p')));
      expect(labels.indexOf('184p'), greaterThan(labels.indexOf('720p')));
      // Cada variante aponta para a URI resolvida do master.
      final v1080 = options.firstWhere((o) => o.label == '1080p');
      expect(v1080.uri.toString(), contains('url_8'));
    });

    test('sem Original quando Automática já é o master', () {
      final options = HlsVariants.qualityOptions(_variants(),
          includeOriginal: false);
      expect(
          options.where((o) => o.id == HlsVariants.originalQualityId),
          isEmpty);
      expect(options.first.id, HlsVariants.autoQualityId);
      expect(options, hasLength(6));
    });

    test('lista vazia gera só Automática (nada inventado)', () {
      final options =
          HlsVariants.qualityOptions(const [], includeOriginal: true);
      expect(options, hasLength(1));
      expect(options.single.id, HlsVariants.autoQualityId);
    });

    test('fetchVariants: master, playlist simples, falha e mp4', () async {
      expect(
        await HlsVariants.fetchVariants(_masterUrl,
            fetchOverride: (_) async => _master),
        hasLength(5),
      );
      expect(
        await HlsVariants.fetchVariants(_masterUrl,
            fetchOverride: (_) async => _media),
        isEmpty,
      );
      expect(
        await HlsVariants.fetchVariants(_masterUrl,
            fetchOverride: (_) =>
                throw const SocketException('sem rede')),
        isEmpty,
      );
      var called = false;
      expect(
        await HlsVariants.fetchVariants('https://midia.test/v.mp4',
            fetchOverride: (_) async {
          called = true;
          return _master;
        }),
        isEmpty,
      );
      expect(called, isFalse);
    });
  });

  group('painel: seção HLS', () {
    Future<void> pumpHlsPanel(
      WidgetTester tester, {
      String selected = HlsVariants.autoQualityId,
      bool includeOriginal = true,
      required List<String> chosen,
    }) async {
      final options = HlsVariants.qualityOptions(_variants(),
          includeOriginal: includeOriginal);
      await tester.pumpWidget(
        _HlsPanelHarness(
          options: options,
          initialSelected: selected,
          chosen: chosen,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lista Automática, Original e variantes disponíveis',
        (tester) async {
      final chosen = <String>[];
      await pumpHlsPanel(tester, chosen: chosen);
      expect(find.text('Automática'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('184p'), findsOneWidget);
    });

    testWidgets('seleção manual e retorno para Automática disparam ids',
        (tester) async {
      final chosen = <String>[];
      await pumpHlsPanel(tester, chosen: chosen);
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(chosen, hasLength(1));
      expect(chosen.single, contains('url_8'));

      // Escolha volta a lista principal; reentrar e voltar a
      // Automatica dispara o id automatico.
      await _reopenQualityFromMainPanel(tester);
      await tester.tap(find.text('Automática'));
      await tester.pumpAndSettle();
      expect(chosen.last, HlsVariants.autoQualityId);
    });

    testWidgets('sem Original duplicado quando automática é o master',
        (tester) async {
      final chosen = <String>[];
      await pumpHlsPanel(tester, chosen: chosen, includeOriginal: false);
      expect(find.text('Original'), findsNothing);
      expect(find.text('Automática'), findsOneWidget);
    });

    testWidgets('barra compacta da TV não expõe Qualidade permanente',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvPlayerControls(
              player: const NoOpMediaPlayerService(),
              session: const PlaybackSession(),
              onOpenPanel: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
      expect(find.byTooltip('Configurações'), findsOneWidget);
    });

    testWidgets('layout Windows (PlayerControls) sem seção de qualidade',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              player: const NoOpMediaPlayerService(),
              session: const PlaybackSession(),
              onOpenSettings: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
      expect(find.byTooltip('Configurações'), findsOneWidget);
    });
  });

  group('player HLS (integração)', () {
    testWidgets('TV: padrão Automática abre variante tetada',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened.single.source, contains('url_4'));
      await _openQualityViaPanel(tester);
      expect(find.text('Automática'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
    });

    testWidgets(
        'TV: manual preserva item, histórico e posição aproximada',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      await harness.player.seek(const Duration(seconds: 42));
      await tester.pumpAndSettle();

      await _openQualityViaPanel(tester);
      await tester.tap(find.text('1080p'));
      // Gate de prontidão (~8 s) + verificação (2 s) da troca.
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      // Reabriu na variante, mesmo id, biblioteca segue no master.
      expect(harness.player.opened.last.source, contains('url_8'));
      expect(harness.player.opened.last.id, 'hls');
      expect(harness.library.findById('hls')!.source, _masterUrl);
      expect(
        (harness.player.session.position - const Duration(seconds: 42))
            .abs(),
        lessThan(const Duration(seconds: 5)),
      );

      // Fechar salva no mesmo histórico (id único), posição ~42s.
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fechar').last);
      await tester.pumpAndSettle();
      final entry = harness.history.latestFor('hls');
      expect(entry, isNotNull);
      expect(
        ((entry!.position ?? Duration.zero) -
                const Duration(seconds: 42))
            .abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    testWidgets('TV: Original abre o master e Automática volta ao teto',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);

      await _openQualityViaPanel(tester);
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, _masterUrl);

      await _reopenQualityFromMainPanel(tester);
      await tester.tap(find.text('Automática'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, contains('url_4'));
    });

    testWidgets('desktop: Automática é o master, manual e retorno funcionam',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester);
      expect(harness.player.opened.single.source, _masterUrl);

      await _openQualityViaPanel(tester);
      // Desktop: Automática já é o master -> sem Original duplicado.
      expect(find.text('Original'), findsNothing);
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, contains('url_0'));

      await _reopenQualityFromMainPanel(tester);
      await tester.tap(find.text('Automática'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, _masterUrl);
    });

    testWidgets('Windows: MP4 único (feed definitivo) sem linha Qualidade',
        (tester) async {
      final harness = await _openPlayer(tester, item: _mp4Item());
      expect(harness.player.opened.single.source, endsWith('.mp4'));

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Idioma'), findsOneWidget);
      expect(find.text('Qualidade'), findsNothing);
    });

    testWidgets('falha da variante: erro controlado e voltar p/ Automática',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      harness.player.failOnContains = 'url_8';

      await _openQualityViaPanel(tester);
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();

      // Erro controlado (overlay), sem texto nativo/URL na tela.
      expect(find.text('Não foi possível reproduzir'), findsOneWidget);
      expect(find.textContaining('url_8'), findsNothing);
      expect(find.text('Voltar para Automática'), findsOneWidget);

      await tester.tap(find.text('Voltar para Automática'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source, contains('url_4'));
      expect(find.text('Não foi possível reproduzir'), findsNothing);
    });

    testWidgets('playlist simples não oferece Qualidade inventada',
        (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _media;
      final harness = await _openPlayer(tester, tvMode: true);
      expect(harness.player.opened.single.source, _masterUrl);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsNothing);
    });

    testWidgets('TV: Opções → Qualidade via D-pad e OK', (tester) async {
      HlsVariants.debugFetchOverride = (_) async => _master;
      final harness = await _openPlayer(tester, tvMode: true);
      await harness.player.seek(const Duration(seconds: 20));
      await tester.pumpAndSettle();

      // Foco inicial no Reproduzir/Pausar; D-pad até Configurações.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Qualidade'), findsOneWidget,
          reason: 'painel de Opções aberto só com D-pad + OK');

      // D-pad (só setas) até o foco cair sobre o alvo rotulado.
      Future<void> dpadTo(String label) async {
        // Escopo modal tem rect de tela cheia: nao conta como alvo.
        bool onTarget() {
          if (find.text(label).evaluate().isEmpty) return false;
          final target = tester.getRect(find.text(label).first);
          final focus = FocusManager.instance.primaryFocus;
          return focus != null &&
              focus is! FocusScopeNode &&
              focus.rect.contains(target.center);
        }

        for (var i = 0; i < 12 && !onTarget(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(onTarget(), isTrue, reason: 'foco do D-pad sobre "$label"');
      }

      await dpadTo('Qualidade');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('1080p'), findsOneWidget,
          reason: 'submenu Qualidade aberto só com D-pad + OK');

      // D-pad até a variante 720p e OK seleciona (reabre nela).
      final before = harness.player.opened.length;
      await dpadTo('720p');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // Gate de prontidão (~8 s) + verificação (2 s) da troca.
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(harness.player.opened.length, greaterThan(before),
          reason: 'variante selecionada só com D-pad + OK');
      expect(harness.player.opened.last.id, 'hls');
      expect(harness.player.opened.last.source, contains('url_0'));
    });
  });
}
