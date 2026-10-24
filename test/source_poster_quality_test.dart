import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/services/sources/demo_source_adapter.dart';
import 'package:player/widgets/media_card.dart';
import 'package:player/widgets/player_panel_options.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/core/errors/app_error.dart';

const qualities = [
  SourceQuality(
    id: 'q720',
    label: '720p',
    sourceUrl: 'https://cdn.demo.invalid/v_720.mp4',
  ),
  SourceQuality(
    id: 'q1080',
    label: '1080p',
    sourceUrl: 'https://cdn.demo.invalid/v_1080.mp4',
  ),
];

MediaItem itemWithQualities() => MediaItem(
      id: 'fonte1',
      title: 'Video da fonte',
      sourceType: MediaSourceType.url,
      source: 'https://cdn.demo.invalid/v.mp4',
      duration: const Duration(minutes: 10),
      addedAt: DateTime(2026, 1, 1),
      metadata: {
        'qualities': encodeSourceQualities(qualities),
      },
    );

class RecordingPlayer extends NoOpMediaPlayerService {
  RecordingPlayer();

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

class FakeAddonFetcher extends AddonFetcher {
  const FakeAddonFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = RecordingPlayer(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final RecordingPlayer player;
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

Future<void> _pumpPanel(
  WidgetTester tester, {
  SourceOptions? source,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerSettingsPanel(
          player: const NoOpMediaPlayerService(),
          session: const PlaybackSession(),
          source: source,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('codec de qualidades', () {
    test('round-trip preserva tudo', () {
      final decoded = decodeSourceQualities(encodeSourceQualities(qualities));
      expect(decoded, hasLength(2));
      expect(decoded.first.id, 'q720');
      expect(decoded.first.label, '720p');
      expect(decoded.first.sourceUrl, 'https://cdn.demo.invalid/v_720.mp4');
    });

    test('corpo estranho vira vazio; ruim pula, bom fica', () {
      for (final bad in [null, '', 'nao-json', '{"a":1}', '[]', '[1]']) {
        expect(decodeSourceQualities(bad), isEmpty, reason: '$bad');
      }
      const mixed = '[{"id":"q1","label":"L","sourceUrl":'
          '"https://cdn.demo.invalid/a.mp4"},'
          '{"id":"ruim"},'
          '{"id":"q2","label":"L2","sourceUrl":"nota-url"}]';
      final decoded = decodeSourceQualities(mixed);
      expect(decoded.map((e) => e.id), ['q1']);
    });
  });

  group('resolve leva poster e rendicoes', () {
    test('demo com tudo vira metadata; sem nada nao cria chave', () async {
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: const FakeAddonFetcher({}),
        adapters: const [DemoSourceAdapter()],
      );
      const withAll = AddonCatalogItem(
        id: 'd1',
        title: 'Demo',
        sourceUrl: 'https://cdn.demo.invalid/d1.mp4',
        thumbnailUrl: 'https://cdn.demo.invalid/d1.jpg',
        qualities: qualities,
      );
      final manifest = const DemoSourceAdapter()
          .manifestFor('https://api.demo.invalid/c', 1);
      await service.install(manifest, originTrusted: false);
      await service.enable('demo.source');
      final media = await service.resolvePlayback('demo.source', withAll);
      expect(media.metadata['posterUrl'], 'https://cdn.demo.invalid/d1.jpg');
      expect(decodeSourceQualities(media.metadata['qualities']), hasLength(2));

      const plain = AddonCatalogItem(
        id: 'd2',
        title: 'Demo',
        sourceUrl: 'https://cdn.demo.invalid/d2.mp4',
      );
      final media2 = await service.resolvePlayback('demo.source', plain);
      expect(media2.metadata.containsKey('posterUrl'), isFalse);
      expect(media2.metadata.containsKey('qualities'), isFalse);
    });
  });

  group('cartao: poster com fallback', () {
    testWidgets('poster chama o builder; sem nada, placeholder',
        (tester) async {
      String? seen;
      final withPoster = MediaItem(
        id: 'p1',
        title: 'Com poster',
        sourceType: MediaSourceType.url,
        source: 'https://cdn.demo.invalid/v.mp4',
        addedAt: DateTime(2026, 1, 1),
        metadata: const {'posterUrl': 'https://cdn.demo.invalid/p.jpg'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaCard(
              item: withPoster,
              networkThumbnailBuilder: (url) {
                seen = url;
                return const Text('POSTER');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, 'https://cdn.demo.invalid/p.jpg');
      expect(find.text('POSTER'), findsOneWidget);
    });

    testWidgets('miniatura local ganha do poster', (tester) async {
      var networkCalled = false;
      final item = MediaItem(
        id: 'p2',
        title: 'Com thumb',
        sourceType: MediaSourceType.local,
        source: '/v.mp4',
        thumbnailPath: '/t.jpg',
        addedAt: DateTime(2026, 1, 1),
        metadata: const {'posterUrl': 'https://cdn.demo.invalid/p.jpg'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaCard(
              item: item,
              thumbnailBuilder: (_) => const Text('ARQUIVO'),
              networkThumbnailBuilder: (_) {
                networkCalled = true;
                return const Text('POSTER');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ARQUIVO'), findsOneWidget);
      expect(networkCalled, isFalse);
    });

    testWidgets('sem thumb nem poster, icone', (tester) async {
      final item = MediaItem(
        id: 'p3',
        title: 'Sem nada',
        sourceType: MediaSourceType.url,
        source: 'https://cdn.demo.invalid/v.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaCard(item: item)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    test('builders padrao tem fallback (sem pump)', () {
      final file = MediaCard.defaultThumbnailImage('/t.jpg') as Image;
      expect(file.errorBuilder, isNotNull);
      final net = MediaCard.defaultNetworkThumbnailImage('https://x/y.jpg')
          as Image;
      expect(net.loadingBuilder, isNotNull);
      expect(net.errorBuilder, isNotNull);
    });

    testWidgets('poster com falha de rede cai no icone', (tester) async {
      final item = MediaItem(
        id: 'p4',
        title: 'Poster quebrado',
        sourceType: MediaSourceType.url,
        source: 'https://cdn.demo.invalid/v.mp4',
        addedAt: DateTime(2026, 1, 1),
        metadata: const {'posterUrl': 'https://cdn.demo.invalid/404.png'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaCard(item: item)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('builders: erro e loading caem no icone (sem decode)',
        (tester) async {
      // Image.file real trava o flutter test no Windows: os builders
      // sao invocados direto, sem passar pelo decode/rede.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('x'))),
      );
      final context = tester.element(find.text('x'));

      final file = MediaCard.defaultThumbnailImage('/nao/existe.jpg')
          as Image;
      final fileFallback =
          file.errorBuilder!(context, Exception('boom'), null) as Icon;
      expect(fileFallback.icon, Icons.play_arrow);

      final net = MediaCard.defaultNetworkThumbnailImage('https://x/y.jpg')
          as Image;
      final netFallback =
          net.errorBuilder!(context, Exception('boom'), null) as Icon;
      expect(netFallback.icon, Icons.play_arrow);

      const child = Text('foto');
      expect(
        net.loadingBuilder!(context, child, null),
        same(child),
      );
      final loading = net.loadingBuilder!(
        context,
        child,
        const ImageChunkEvent(
          cumulativeBytesLoaded: 1,
          expectedTotalBytes: 10,
        ),
      ) as Icon;
      expect(loading.icon, Icons.play_arrow);
    });
  });

  group('painel: rendicoes da fonte', () {
    testWidgets('lista rendicoes e marca a atual', (tester) async {
      String? chosen;
      await _pumpPanel(
        tester,
        source: SourceOptions(
          qualities: qualities,
          selectedId: 'q720',
          onSelect: (id) async => chosen = id,
        ),
      );
      expect(find.text('Qualidade'), findsOneWidget);
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();

      expect(find.text('Da fonte'), findsOneWidget);
      expect(find.text('Padrão da fonte'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(chosen, 'q1080');
      // Escolha volta a lista principal.
      expect(find.text('Idioma'), findsOneWidget);
    });

    testWidgets('sem rendicoes, sem secao da fonte', (tester) async {
      await _pumpPanel(tester);
      // Nem faixa de video nem rendicao: sem linha de qualidade.
      expect(find.text('Qualidade'), findsNothing);
    });
  });

  group('tela: troca de rendicao reabre com posicao', () {
    testWidgets('720p troca a fonte e mantem id e posicao', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      final item = itemWithQualities();
      await harness.library.upsert(item);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
      await tester.pumpAndSettle();

      await harness.player.seek(const Duration(seconds: 42));
      final opens = harness.player.opened.length;
      final seeks = harness.player.seeks.length;

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();

      expect(harness.player.opened, hasLength(opens + 1));
      final reopened = harness.player.opened.last;
      expect(reopened.id, 'fonte1');
      expect(reopened.source, 'https://cdn.demo.invalid/v_720.mp4');
      expect(harness.player.seeks, hasLength(seeks + 1));
      expect(harness.player.seeks.last, const Duration(seconds: 42));
    });

    testWidgets('padrao volta a URL original', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      final item = itemWithQualities();
      await harness.library.upsert(item);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source,
          'https://cdn.demo.invalid/v_1080.mp4');

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qualidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Padrão da fonte'));
      await tester.pumpAndSettle();
      expect(harness.player.opened.last.source,
          'https://cdn.demo.invalid/v.mp4');
      expect(harness.player.opened.last.id, 'fonte1');
    });
  });
}
