import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/media_card.dart';
import 'package:player/widgets/player_controls.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/tv_player_controls.dart';

void main() {
  /// Bomba [getter] sob `MediaQuery` explicito (tamanho logico) e modo
  /// TV opcional; `setSurfaceSize` nao alcanca a view implicita que o
  /// `MediaQuery.sizeOf` le neste Flutter.
  Future<T> pumpValue<T>(
    WidgetTester tester,
    T Function(BuildContext context) getter, {
    Size surface = const Size(800, 600),
    bool tvMode = false,
  }) async {
    late T result;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: surface),
          child: TvMode(
            enabled: tvMode,
            child: Builder(
              builder: (context) {
                result = getter(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return result;
  }

  group('TvLayout contexto (spec 27.3/27.4)', () {
    testWidgets('largura abaixo de 800 e compacto', (tester) async {
      // TV 720p em 320 dpi informa 640x360.
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(640, 360), tvMode: true),
        TvWidthClass.compact,
      );
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(799, 600)),
        TvWidthClass.compact,
      );
    });

    testWidgets('800 ate 1279 e normal', (tester) async {
      // TV 1080p em 320 dpi informa 960x540.
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(960, 540), tvMode: true),
        TvWidthClass.normal,
      );
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(800, 600)),
        TvWidthClass.normal,
      );
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(1279, 800)),
        TvWidthClass.normal,
      );
    });

    testWidgets('1280 ou mais e grande', (tester) async {
      // TV 4K em 320 dpi informa 1920x1080.
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(1920, 1080), tvMode: true),
        TvWidthClass.big,
      );
      expect(
        await pumpValue(tester, TvLayout.widthClassOf,
            surface: const Size(1280, 720)),
        TvWidthClass.big,
      );
    });

    testWidgets('ultrawide so no desktop (proporcao > 1.90)',
        (tester) async {
      expect(
        await pumpValue(tester, TvLayout.isUltrawide,
            surface: const Size(1920, 800)),
        isTrue,
      );
      expect(
        await pumpValue(tester, TvLayout.isUltrawide,
            surface: const Size(1920, 800), tvMode: true),
        isFalse,
      );
      expect(
        await pumpValue(tester, TvLayout.isUltrawide,
            surface: const Size(960, 540), tvMode: true),
        isFalse,
      );
    });

    testWidgets('margem segura e 5% da menor dimensao (16..48)',
        (tester) async {
      // 540 * 0.05 = 27 na TV 1080p.
      expect(
        await pumpValue(tester, TvLayout.safeMarginOf,
            surface: const Size(960, 540), tvMode: true),
        closeTo(27, 0.01),
      );
      // 300 * 0.05 = 15, preso no minimo.
      expect(
        await pumpValue(tester, TvLayout.safeMarginOf,
            surface: const Size(400, 300), tvMode: true),
        16,
      );
      // 1080 * 0.05 = 54, preso no maximo.
      expect(
        await pumpValue(tester, TvLayout.safeMarginOf,
            surface: const Size(1920, 1080), tvMode: true),
        48,
      );
    });

    testWidgets('e TV so com o modo ligado', (tester) async {
      expect(
        await pumpValue(tester, TvLayout.isTv,
            surface: const Size(960, 540)),
        isFalse,
      );
      expect(
        await pumpValue(tester, TvLayout.isTv,
            surface: const Size(960, 540), tvMode: true),
        isTrue,
      );
    });
  });

  group('TvLayoutTokens (spec 27.7)', () {
    test('conjuntos por classe', () {
      final compact = TvLayoutTokens.forClass(TvWidthClass.compact);
      final normal = TvLayoutTokens.forClass(TvWidthClass.normal);
      final big = TvLayoutTokens.forClass(TvWidthClass.big);
      // Primario cresce; secundario nao acompanha na mesma proporcao.
      expect(
          [compact.iconPrimary, normal.iconPrimary, big.iconPrimary],
          [28, 32, 36]);
      expect(
          [compact.iconSecondary, normal.iconSecondary, big.iconSecondary],
          [20, 24, 28]);
      expect(
          [compact.controlHeight, normal.controlHeight, big.controlHeight],
          [52, 56, 64]);
      expect([compact.textTitle, normal.textTitle, big.textTitle],
          [20, 22, 24]);
      expect([compact.textBody, normal.textBody, big.textBody],
          [15, 17, 19]);
      expect(normal.minTextScale, 1.15);
      expect(normal.maxTextScale, 1.3);
    });

    testWidgets('alvo minimo: 44 fora, tokens na TV', (tester) async {
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(960, 540)),
        44,
      );
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(640, 360), tvMode: true),
        52,
      );
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(960, 540), tvMode: true),
        56,
      );
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(1920, 1080), tvMode: true),
        64,
      );
    });

    testWidgets('espaco: fator da classe na TV, 1.0 fora',
        (tester) async {
      Future<double> gap(Size surface, bool tv) => pumpValue(
          tester, (c) => TvLayout.spacing(c, 12),
          surface: surface, tvMode: tv);
      expect(await gap(const Size(960, 540), false), 12);
      expect(await gap(const Size(640, 360), true), 15);
      expect(await gap(const Size(960, 540), true), 18);
      expect(await gap(const Size(1920, 1080), true), 21);
    });
  });

  group('PlayerTheme', () {
    test('desktop mantem as metricas atuais', () {
      final theme = PlayerTheme.dark();
      expect(theme.iconTheme.size, 24);
      expect(theme.appBarTheme.toolbarHeight, isNull);
      expect(theme.sliderTheme.trackHeight, 4);
      expect(
        (theme.sliderTheme.thumbShape as RoundSliderThumbShape)
            .enabledThumbRadius,
        10,
      );
      expect(
        theme.listTileTheme.contentPadding!
            .resolve(TextDirection.ltr)
            .left,
        16,
      );
      expect(theme.listTileTheme.minVerticalPadding, 4);
    });

    test('tvMode e a base da classe normal', () {
      final theme = PlayerTheme.dark(tvMode: true);
      expect(theme.iconTheme.size, 32);
      expect(theme.appBarTheme.toolbarHeight, 72);
      expect(theme.sliderTheme.trackHeight, 6);
      expect(
        (theme.sliderTheme.thumbShape as RoundSliderThumbShape)
            .enabledThumbRadius,
        14,
      );
      expect(
        theme.listTileTheme.contentPadding!
            .resolve(TextDirection.ltr)
            .left,
        24,
      );
      expect(theme.listTileTheme.minVerticalPadding, 10);
    });
  });

  group('TvPlayerControls (spec 27.6)', () {
    Future<void> pumpTv(
      WidgetTester tester, {
      Size surface = const Size(960, 540),
      PlaybackSession session = const PlaybackSession(),
      List<SourceQuality> qualities = const [],
      ValueNotifier<String?>? selectedQuality,
      void Function(PlayerPanelView, BuildContext)? onOpenPanel,
    }) async {
      // Tamanho real da view: o LayoutBuilder da barra usa as
      // restricoes de layout, nao o MediaQuery.
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: TvMode(
            enabled: true,
            child: Scaffold(
              body: TvPlayerControls(
                player: const NoOpMediaPlayerService(),
                session: session,
                videoTitle: 'Noite',
                sourceQualities: qualities,
                sourceQualityListenable: selectedQuality,
                onOpenPanel: onOpenPanel ?? (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('acoes principais + chips com rotulo textual',
        (tester) async {
      await pumpTv(tester);
      expect(find.byTooltip('Reproduzir'), findsOneWidget);
      expect(find.byTooltip('Retroceder 10 segundos'), findsOneWidget);
      expect(find.byTooltip('Avançar 10 segundos'), findsOneWidget);
      expect(find.byTooltip('Configurações'), findsOneWidget);
      expect(find.text('Noite'), findsOneWidget);
      expect(find.text('Áudio'), findsOneWidget);
      expect(find.text('Padrão'), findsOneWidget);
      expect(find.text('Legendas'), findsOneWidget);
      expect(find.text('Desativadas'), findsOneWidget);
      expect(find.text('Qualidade'), findsOneWidget);
      expect(find.text('Automática'), findsOneWidget);
    });

    testWidgets('largura limitada: 72% ate 760', (tester) async {
      Finder maxWidth(double want) => find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                (widget.constraints.maxWidth - want).abs() < 0.5,
          );
      await pumpTv(tester, surface: const Size(960, 540));
      expect(maxWidth(960 * 0.72), findsOneWidget);
      await pumpTv(tester, surface: const Size(1920, 1080));
      expect(maxWidth(760), findsOneWidget);
      await pumpTv(tester, surface: const Size(640, 360));
      expect(maxWidth(640 * 0.72), findsOneWidget);
    });

    testWidgets('chip abre o subpainel correspondente', (tester) async {
      PlayerPanelView? opened;
      await pumpTv(tester, onOpenPanel: (view, _) => opened = view);
      await tester.tap(find.text('Padrão'));
      expect(opened, PlayerPanelView.audio);
      await tester.tap(find.text('Desativadas'));
      expect(opened, PlayerPanelView.subtitles);
      await tester.tap(find.text('Automática'));
      expect(opened, PlayerPanelView.quality);
    });

    testWidgets('rotulo da qualidade acompanha a troca ao vivo',
        (tester) async {
      final selected = ValueNotifier<String?>(null);
      addTearDown(selected.dispose);
      await pumpTv(
        tester,
        qualities: const [
          SourceQuality(
              id: 'q1',
              label: '720p',
              sourceUrl: 'https://example.com/q1.m3u8'),
        ],
        selectedQuality: selected,
      );
      expect(find.text('Automática'), findsOneWidget);
      selected.value = 'q1';
      await tester.pump();
      expect(find.text('720p'), findsOneWidget);
    });
  });

  group('widgets na TV usam os tokens', () {
    MediaItem plainItem() => MediaItem(
          id: 's1',
          title: 'Sem imagem',
          sourceType: MediaSourceType.local,
          source: '/v.mp4',
          addedAt: DateTime(2026, 1, 1),
        );

    testWidgets('cartao: placeholder 28 fora, primario na TV',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaCard(item: plainItem())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Icon>(find.byIcon(Icons.play_arrow)).size,
        28,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(960, 540)),
            child: TvMode(
              enabled: true,
              child: Scaffold(body: MediaCard(item: plainItem())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Icon>(find.byIcon(Icons.play_arrow)).size,
        32,
      );
    });

    testWidgets('PlayerControls e desktop: trilhos 72/56 fixos',
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
      Finder boxWidth(double w) => find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox &&
                widget.width == w &&
                widget.height == null,
          );
      expect(boxWidth(72), findsOneWidget);
      expect(boxWidth(56), findsNWidgets(2));
    });
  });
}
