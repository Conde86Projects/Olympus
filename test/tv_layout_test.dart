import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/tv_mode.dart';
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

    testWidgets('ultrawide so no desktop (proporcao > 1.90)', (tester) async {
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
        await pumpValue(tester, TvLayout.isTv, surface: const Size(960, 540)),
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
      expect([compact.iconPrimary, normal.iconPrimary, big.iconPrimary],
          [20, 24, 28]);
      expect([compact.iconSecondary, normal.iconSecondary, big.iconSecondary],
          [16, 18, 20]);
      expect([compact.controlHeight, normal.controlHeight, big.controlHeight],
          [44, 44, 52]);
      expect(
          [compact.textTitle, normal.textTitle, big.textTitle], [20, 22, 24]);
      expect([compact.textBody, normal.textBody, big.textBody], [15, 17, 19]);
      expect(normal.minTextScale, 1.0);
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
        44,
      );
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(960, 540), tvMode: true),
        44,
      );
      expect(
        await pumpValue(tester, TvLayout.minTarget,
            surface: const Size(1920, 1080), tvMode: true),
        52,
      );
    });

    testWidgets('espaco: fator da classe na TV, 1.0 fora', (tester) async {
      Future<double> gap(Size surface, bool tv) =>
          pumpValue(tester, (c) => TvLayout.spacing(c, 12),
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
        theme.listTileTheme.contentPadding!.resolve(TextDirection.ltr).left,
        16,
      );
      expect(theme.listTileTheme.minVerticalPadding, 4);
    });

    test('icone focado na TV ganha anel visivel; desktop intacto', () {
      // O estado padrao do M3 (branco ~10%) sumia no fundo da TV: o foco
      // subia para a AppBar e parecia ter desaparecido.
      final tv = PlayerTheme.dark(tvMode: true).iconButtonTheme.style!;
      final ring = tv.side!.resolve({WidgetState.focused})!;
      expect(ring.color, PlayerTheme.accent);
      expect(ring.width, 2);
      expect(tv.side!.resolve(<WidgetState>{}), isNull);
      expect(tv.overlayColor!.resolve({WidgetState.focused}), isNotNull);
      expect(PlayerTheme.dark().iconButtonTheme.style, isNull);
    });

    test('tvMode e a base da classe normal', () {
      final theme = PlayerTheme.dark(tvMode: true);
      expect(theme.iconTheme.size, 24);
      expect(theme.appBarTheme.toolbarHeight, 72);
      expect(theme.sliderTheme.trackHeight, 6);
      expect(
        (theme.sliderTheme.thumbShape as RoundSliderThumbShape)
            .enabledThumbRadius,
        14,
      );
      expect(
        theme.listTileTheme.contentPadding!.resolve(TextDirection.ltr).left,
        24,
      );
      expect(theme.listTileTheme.minVerticalPadding, 10);
    });

    test('menus da TV (AppShell) ficam compactos na classe normal', () {
      final theme = PlayerTheme.tvMenus(
          PlayerTheme.dark(tvMode: true), TvWidthClass.normal);
      expect(theme.iconTheme.size, 22);
      expect(theme.appBarTheme.toolbarHeight, 52);
      expect(theme.appBarTheme.titleTextStyle!.fontSize, 19);
      expect(theme.listTileTheme.titleTextStyle!.fontSize, 14);
      expect(theme.listTileTheme.subtitleTextStyle!.fontSize, 12);
      expect(
          theme.listTileTheme.visualDensity, const VisualDensity(vertical: -4));
      expect(theme.textTheme.titleLarge!.fontSize, 20);
      expect(theme.textTheme.titleMedium!.fontSize, 15);
      expect(theme.sliderTheme.trackHeight, 3);
    });
  });

  group('TvPlayerControls (spec 27.6)', () {
    Future<void> pumpTv(
      WidgetTester tester, {
      Size surface = const Size(960, 540),
      PlaybackSession session = const PlaybackSession(),
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
                onOpenPanel: onOpenPanel ?? (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('perfil compacto: 7 elementos, sem chips', (tester) async {
      await pumpTv(
        tester,
        session: const PlaybackSession(
          duration: Duration(minutes: 10, seconds: 34),
        ),
      );
      expect(find.byTooltip('Reproduzir'), findsOneWidget);
      expect(find.byTooltip('Retroceder 10 segundos'), findsOneWidget);
      expect(find.byTooltip('Avançar 10 segundos'), findsOneWidget);
      expect(find.byTooltip('Silenciar'), findsOneWidget);
      expect(find.byTooltip('Configurações'), findsOneWidget);
      expect(find.text('Noite'), findsOneWidget);
      expect(find.text('10:34'), findsOneWidget);
      expect(find.text('Áudio'), findsNothing);
      expect(find.text('Legendas'), findsNothing);
      expect(find.text('Qualidade'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('titulo em uma linha com reticencias', (tester) async {
      await pumpTv(tester);
      final title = tester.widget<Text>(find.text('Noite'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('largura limitada: 50% ate 460', (tester) async {
      Finder maxWidth(double want) => find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                (widget.constraints.maxWidth - want).abs() < 0.5,
          );
      await pumpTv(tester, surface: const Size(960, 540));
      expect(maxWidth(460), findsOneWidget);
      await pumpTv(tester, surface: const Size(1920, 1080));
      expect(maxWidth(460), findsOneWidget);
      await pumpTv(tester, surface: const Size(640, 360));
      expect(maxWidth(640 * 0.50), findsOneWidget);
    });

    testWidgets('TCL 960x540: painel 430-480 x 105-125', (tester) async {
      await pumpTv(
        tester,
        session: const PlaybackSession(
          duration: Duration(minutes: 10, seconds: 34),
        ),
      );
      final panel = tester.getSize(
        find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              (widget.constraints.maxWidth - 460).abs() < 0.5,
        ),
      );
      expect(panel.width, inInclusiveRange(430, 480));
      expect(panel.height, inInclusiveRange(105, 125));
    });

    testWidgets('sem trilho de volume: so o progresso', (tester) async {
      await pumpTv(tester);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Silenciar'), findsOneWidget);
    });

    testWidgets('botoes de 36, glifos de 20', (tester) async {
      await pumpTv(tester);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is SizedBox && widget.width == 36 && widget.height == 36),
        findsNWidgets(5),
      );
      final bar = find.byType(TvPlayerControls);
      expect(
        find.descendant(
            of: bar,
            matching: find.byWidgetPredicate(
                (widget) => widget is IconTheme && widget.data.size == 20)),
        findsWidgets,
      );
      expect(
        find.descendant(
            of: bar,
            matching: find.byWidgetPredicate(
                (widget) => widget is IconTheme && widget.data.size == 24)),
        findsNothing,
      );
    });

    testWidgets('progresso extra-fino: trilho 3, dedao 8', (tester) async {
      await pumpTv(tester);
      final theme = SliderTheme.of(
        tester.element(find.byType(Slider)),
      );
      expect(theme.trackHeight, 3);
      expect(
        (theme.thumbShape as RoundSliderThumbShape).enabledThumbRadius,
        8,
      );
      expect(
        (theme.overlayShape as RoundSliderOverlayShape).overlayRadius,
        10,
      );
    });

    testWidgets('engrenagem abre o painel de Opcoes', (tester) async {
      PlayerPanelView? opened;
      await pumpTv(tester, onOpenPanel: (view, _) => opened = view);
      await tester.tap(find.byTooltip('Configurações'));
      expect(opened, PlayerPanelView.main);
    });

    testWidgets('layout registra as metricas reais', (tester) async {
      TvPanelMetrics.reset();
      addTearDown(TvPanelMetrics.reset);
      await pumpTv(tester, surface: const Size(960, 540));
      final metrics = TvPanelMetrics.current.value!;
      expect(metrics.constraints.maxWidth, 960);
      expect(metrics.appliedMaxWidth, closeTo(460, 0.5));
    });
  });

  group('PlayerSettingsPanel na TV (spec 27.6)', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      Size surface = const Size(960, 540),
      bool tvMode = true,
      double? maxHeight,
      PlaybackSession session = const PlaybackSession(),
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: TvMode(
            enabled: tvMode,
            child: Scaffold(
              body: Center(
                child: PlayerSettingsPanel(
                  player: const NoOpMediaPlayerService(),
                  session: session,
                  maxHeight: maxHeight,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    PlaybackSession fullSession() => const PlaybackSession(
          videoTracks: [
            MediaTrack(id: 'v1', label: 'HD'),
            MediaTrack(id: 'v2', label: 'Full HD'),
          ],
        );

    testWidgets('linhas de 34, painel cabe no teto da TCL', (tester) async {
      await pumpPanel(tester, session: fullSession(), maxHeight: 384);
      for (final label in [
        'Idioma',
        'Legendas',
        'Repetir',
        'Qualidade',
        'Girar',
        'Informações do vídeo',
      ]) {
        final tile = find.ancestor(
          of: find.text(label),
          matching: find.byType(ListTile),
        );
        expect(tester.getSize(tile).height, 34);
      }
      // Seis linhas + velocidade + fechar: 319, com folga no teto 384.
      expect(tester.getSize(find.byType(PlayerSettingsPanel)).height,
          lessThanOrEqualTo(330));
    });

    testWidgets('teto baixo rola em vez de estourar', (tester) async {
      await pumpPanel(tester, session: fullSession(), maxHeight: 200);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.getSize(find.byType(PlayerSettingsPanel)).height, 200);
    });

    testWidgets('desktop: sem teto, linhas de 52', (tester) async {
      await pumpPanel(tester, tvMode: false, session: fullSession());
      expect(find.byType(SingleChildScrollView), findsNothing);
      final tile = find.ancestor(
        of: find.text('Idioma'),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(tile).height, 52);
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

    testWidgets('cartao: placeholder 28 fora, primario na TV', (tester) async {
      Finder thumbBox() => find.ancestor(
            of: find.byIcon(Icons.play_arrow),
            matching: find.byType(Container),
          );
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
      expect(tester.getSize(thumbBox()), const Size(96, 56));

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
        24,
      );
      expect(tester.getSize(thumbBox()), const Size(96, 56));
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
