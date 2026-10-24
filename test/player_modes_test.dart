import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_settings_panel.dart';

/// Monta o app com implementacoes em memoria e expoe os servicos para
/// assercao.
class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    // Testes partem da tela inicial: dispensa a apresentacao (ela tem
    // teste proprio). O update em memoria aplica de imediato.
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
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
        mobileChromeService: SystemMobileChrome(),
      );
}

MediaItem _item() => MediaItem(
      id: 'modos',
      title: 'Vídeo de teste',
      sourceType: MediaSourceType.url,
      source: 'https://exemplo.com/v.mp4',
      addedAt: DateTime(2026, 1, 1),
    );

Future<void> _openPlayer(
    WidgetTester tester, _Harness harness, MediaItem item) async {
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
}

void main() {
  group('modos e atalhos do player', () {
    testWidgets('cinema oculta a barra; C e Esc restauram',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      await tester.tap(find.byTooltip('Modo cinema'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsOneWidget);

      await tester.tap(find.byTooltip('Modo cinema'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsOneWidget);
    });

    testWidgets('I, S e A abrem o painel direto na subview',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      // Informacoes: subview sem a lista principal.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text('Voltar'), findsOneWidget);
      expect(find.text('Velocidade de reprodução'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Voltar'), findsNothing);

      // Legendas: lista vazia com a opcao de desativar.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma legenda disponível'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Audio: lista vazia.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma faixa disponível'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma faixa disponível'), findsNothing);
    });

    testWidgets('tela cheia reflete o estado no botao', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);

      await tester.tap(find.byTooltip('Sair da tela cheia'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tela cheia'), findsOneWidget);
    });

    testWidgets('fim do video oferece rever, favoritar e fechar',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      final item = _item();
      await _openPlayer(tester, harness, item);

      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();
      expect(find.text('Reprodução concluída'), findsOneWidget);

      // Rever volta a reproduzir e dispensa as acoes.
      await tester.tap(
          find.widgetWithText(FocusableButton, 'Reproduzir novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Reprodução concluída'), findsNothing);

      // Favoritar atualiza a biblioteca e o rotulo.
      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FocusableButton, 'Adicionar aos favoritos'));
      await tester.pumpAndSettle();
      expect(harness.library.findById(item.id)!.isFavorite, isTrue);
      expect(find.widgetWithText(
          FocusableButton, 'Remover dos favoritos'), findsOneWidget);

      // Fechar volta para a tela anterior.
      await tester
          .tap(find.widgetWithText(FocusableButton, 'Fechar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsNothing);
    });

    testWidgets('concluído no desktop: sólido, dimensões intactas',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();

      final card = tester.widget<Container>(find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                PlayerSettingsPanel.panelColor,
      ));
      expect((card.decoration as BoxDecoration).color!.a, 1.0);
      expect(card.padding,
          const EdgeInsets.symmetric(horizontal: 20, vertical: 16));
      final title =
          tester.widget<Text>(find.text('Reprodução concluída'));
      expect(title.style!.fontSize, isNull);
      final wrap = tester.widget<Wrap>(find
          .ancestor(
            of: find.text('Reproduzir novamente'),
            matching: find.byType(Wrap),
          )
          .first);
      expect(wrap.spacing, 12);
      expect(wrap.runSpacing, 12);
    });
  });

  group('card flutuante (Showtime)', () {
    testWidgets('card mostra titulo e cantos; X sai salvando',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      // Card fosco com o titulo; cantos com acoes e fechar.
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Vídeo de teste'), findsOneWidget);
      expect(find.byTooltip('Tela cheia'), findsOneWidget);
      expect(find.byTooltip('Modo cinema'), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
    });

    testWidgets('janela estreita esconde o trilho de volume',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, _item());

      // So o progresso; o mudo continua.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Silenciar'), findsOneWidget);
    });
  });

  group('nomes de idioma', () {
    test('conhece ISO 639-1, 639-2 e regiao', () {
      expect(languageDisplayName('por'), 'português');
      expect(languageDisplayName('pt-BR'), 'português');
      expect(languageDisplayName('ENG'), 'inglês');
      expect(languageDisplayName('es'), 'espanhol');
      expect(languageDisplayName('fre'), 'francês');
      expect(languageDisplayName('und'), 'indefinido');
    });

    test('desconhecido volta como esta, nunca em branco', () {
      expect(languageDisplayName('xx'), 'xx');
      expect(languageDisplayName('  xx  '), 'xx');
    });

    test('casa faixa por codigo e por rotulo', () {
      const tracks = [
        MediaTrack(id: 'a1', label: 'English', language: 'eng'),
        MediaTrack(id: 'a2', label: 'Comentários', language: 'por'),
      ];
      expect(findTrackForLanguage(tracks, 'por'), 'a2');
      expect(findTrackForLanguage(tracks, 'POR'), 'a2');
      expect(findTrackForLanguage(tracks, 'english'), 'a1');
      expect(findTrackForLanguage(tracks, 'fra'), isNull);
      expect(findTrackForLanguage(tracks, null), isNull);
      expect(findTrackForLanguage(tracks, '  '), isNull);
    });
  });

  group('rotulo de proveniencia', () {
    MediaItem item({
      MediaSourceType type = MediaSourceType.url,
      Map<String, String> metadata = const {},
    }) =>
        MediaItem(
          id: 'x',
          title: 'X',
          sourceType: type,
          source: 'https://exemplo.com/x.mp4',
          addedAt: DateTime(2026, 1, 1),
          metadata: metadata,
        );

    test('local, add-on e link', () {
      expect(sourceLabelFor(item(type: MediaSourceType.local)),
          'Arquivo local');
      expect(sourceLabelFor(item()), 'Link');
      expect(
          sourceLabelFor(item(metadata: const {
            'addonId': 'demo.catalogo',
            'addonName': 'Catálogo Demo',
          })),
          'Add-on Catálogo Demo');
    });

    test('resolucao de add-on grava proveniencia sem traduzir', () async {
      final harness = _Harness();
      await harness.addons.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: false,
      );
      await harness.addons.enable('demo.catalogo');
      final resolved = await harness.addons.resolvePlayback(
        'demo.catalogo',
        const AddonCatalogItem(
          id: 'aurora',
          title: 'Aurora Demo',
          sourceUrl: 'https://exemplo.com/demo/aurora.mp4',
        ),
      );

      expect(resolved.title, 'Aurora Demo');
      expect(sourceLabelFor(resolved), 'Add-on Catálogo Demo');
    });
  });

  group('idiomas no painel (Task 11)', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      PlaybackSession session = const PlaybackSession(),
      PlayerPanelView view = PlayerPanelView.main,
      String? videoTitle,
      String? preferredAudio,
      String? preferredSubtitle,
      String? sourceLabel,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSettingsPanel(
              player: const NoOpMediaPlayerService(),
              session: session,
              videoTitle: videoTitle,
              preferredAudio: preferredAudio,
              preferredSubtitle: preferredSubtitle,
              sourceLabel: sourceLabel,
              initialView: view,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('audio sem o preferido avisa no submenu', (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.audio,
        preferredAudio: 'por',
        session: const PlaybackSession(
          audioTracks: [
            MediaTrack(id: 'a1', label: 'English', language: 'eng'),
          ],
        ),
      );

      expect(find.text('Sem faixa em português.'), findsOneWidget);
      // Segue no submenu, sem sair do player.
      expect(find.text('Idioma'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('inglês'), findsOneWidget);
    });

    testWidgets('audio com o preferido nao avisa', (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.audio,
        preferredAudio: 'por',
        session: const PlaybackSession(
          audioTracks: [
            MediaTrack(id: 'a1', label: 'English', language: 'eng'),
            MediaTrack(id: 'a2', label: 'Português', language: 'por'),
          ],
        ),
      );

      expect(find.textContaining('Sem faixa em'), findsNothing);
    });

    testWidgets('legenda sem o preferido avisa e mantem opcoes',
        (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.subtitles,
        preferredSubtitle: 'por',
        session: const PlaybackSession(),
      );

      expect(find.text('Sem faixa em português.'), findsOneWidget);
      expect(find.text('Desativadas'), findsOneWidget);
      expect(find.text('Nenhuma legenda disponível'), findsOneWidget);
    });

    testWidgets('sem preferencia nao ha aviso', (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.audio,
        session: const PlaybackSession(
          audioTracks: [
            MediaTrack(id: 'a1', label: 'English', language: 'eng'),
          ],
        ),
      );

      expect(find.textContaining('Sem faixa em'), findsNothing);
    });

    testWidgets('rotulo de faixa passa integro, sem traducao',
        (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.audio,
        session: const PlaybackSession(
          audioTracks: [
            MediaTrack(
                id: 'a1',
                label: "Director's commentary",
                language: 'eng'),
          ],
        ),
      );

      expect(find.text("Director's commentary"), findsOneWidget);
      expect(find.text('inglês'), findsOneWidget);
    });

    testWidgets('info mostra titulo integro e fonte', (tester) async {
      await pumpPanel(
        tester,
        view: PlayerPanelView.info,
        videoTitle: 'Aurora Demo',
        sourceLabel: 'Arquivo local',
      );

      expect(find.text('Aurora Demo'), findsOneWidget);
      expect(find.text('Fonte: Arquivo local'), findsOneWidget);
    });

    testWidgets('player local informa arquivo local', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(
        tester,
        harness,
        MediaItem(
          id: 'local',
          title: 'Férias no parque',
          sourceType: MediaSourceType.local,
          source: r'C:\Videos\parque.mp4',
          addedAt: DateTime(2026, 1, 1),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text('Fonte: Arquivo local'), findsOneWidget);
      expect(find.text('Férias no parque'), findsWidgets);
    });

    testWidgets('player de add-on informa o add-on', (tester) async {
      final harness = _Harness();
      await harness.addons.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: false,
      );
      await harness.addons.enable('demo.catalogo');
      final resolved = await harness.addons.resolvePlayback(
        'demo.catalogo',
        const AddonCatalogItem(
          id: 'aurora',
          title: 'Aurora Demo',
          sourceUrl: 'https://exemplo.com/demo/aurora.mp4',
        ),
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _openPlayer(tester, harness, resolved);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text('Fonte: Add-on Catálogo Demo'), findsOneWidget);
      expect(find.text('Aurora Demo'), findsWidgets);
    });
  });
}
