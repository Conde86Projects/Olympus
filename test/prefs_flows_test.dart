import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/focusable_button.dart';

/// Monta o app com implementacoes em memoria e expoe os servicos para
/// assercao. Por padrao dispensa a apresentacao inicial.
class _Harness {
  _Harness({bool skipOnboarding = true})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    if (skipOnboarding) {
      preferences.update(
          preferences.current.copyWith(showOnboarding: false));
    }
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
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }
}

MediaItem _item({
  String id = 'prefs',
  String title = 'Vídeo prefs',
  String source = 'https://exemplo.com/v.mp4',
  Duration? lastPosition,
  Duration? duration,
}) =>
    MediaItem(
      id: id,
      title: title,
      sourceType: source.startsWith('http')
          ? MediaSourceType.url
          : MediaSourceType.local,
      source: source,
      lastPosition: lastPosition,
      duration: duration,
      addedAt: DateTime(2026, 1, 1),
    );

Future<void> _openPlayer(
    WidgetTester tester, _Harness harness, MediaItem item) async {
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
}

/// Superficie alta para as configuracoes caberem sem rolagem. Usa
/// `setSurfaceSize`: `tester.view.physicalSize` e ignorado na view
/// implicita (createViewConfigurationFor usa _surfaceSize).
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('apresentação inicial', () {
    testWidgets('primeira execução mostra e Começar vai para a inicial',
        (tester) async {
      final harness = _Harness(skipOnboarding: false);
      await harness.pump(tester);

      expect(find.text('Assista sem complicação'), findsOneWidget);
      await tester.tap(find.widgetWithText(FocusableButton, 'Começar'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
      expect(harness.preferences.current.showOnboarding, isFalse);
    });

    testWidgets('Abrir vídeo dispensa e vai para a abertura',
        (tester) async {
      final harness = _Harness(skipOnboarding: false);
      await harness.pump(tester);

      await tester.tap(find.widgetWithText(FocusableButton, 'Abrir vídeo'));
      await tester.pumpAndSettle();

      expect(find.text('Procurar arquivo…'), findsOneWidget);
      expect(harness.preferences.current.showOnboarding, isFalse);
    });
  });

  group('configurações', () {
    testWidgets('toggles de reprodução e janela atualizam as prefs',
        (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reproduzir ao abrir'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.autoplay, isTrue);

      await tester.tap(find.text('Retomar de onde parou'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.resumeAutomatically, isFalse);

      await tester.tap(find.text('Animações'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.animations, isFalse);

      await tester.tap(find.text('Restaurar tamanho e posição'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.restoreWindowGeometry, isFalse);

      await tester.tap(find.text('Ativar por padrão'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.subtitlesByDefault, isTrue);
    });

    testWidgets('volume inicial e idiomas preferidos', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.initialVolume, lessThan(1.0));

      // Idiomas pelo seletor navegável (sem campo de texto: na TV o
      // IME come as setas e o D-pad prendia).
      final rows = find.widgetWithText(ListTile, 'Idioma preferido');
      expect(rows, findsNWidgets(2));
      await tester.tap(rows.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('português'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.defaultSubtitle, 'por');

      await tester.tap(rows.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('inglês'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.defaultAudio, 'eng');
    });

    testWidgets('TV: sem trilho de volume inicial (vale o volume da TV)',
        (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.preferences.update(
          harness.preferences.current.copyWith(tvMode: true));
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      expect(find.text('Usa o volume do aparelho (só o mudo no app)'),
          findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('seção de atalhos lista as teclas', (tester) async {
      await _tallSurface(tester);
      final harness = _Harness();
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      expect(find.text('Atalhos'), findsOneWidget);
      expect(find.text('Reproduzir / pausar'), findsOneWidget);
      expect(find.text('Informações do vídeo'), findsOneWidget);
      expect(find.text('Modo cinema'), findsOneWidget);
    });
  });

  group('preferências de reprodução', () {
    testWidgets('lembrar posição desligado não salva nada',
        (tester) async {
      final harness = _Harness();
      await harness.preferences.update(harness.preferences.current
          .copyWith(rememberPosition: false));
      await harness.pump(tester);
      await _openPlayer(tester, harness, _item());

      // Avança pela barra (Fase 4: setas com controles visíveis
      // navegam o foco; a busca por seta é só com eles ocultos).
      await tester.tap(find.byTooltip('Avançar 10 segundos'));
      await tester.pumpAndSettle();
      expect(harness.player.session.position,
          const Duration(seconds: 10));

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(harness.history.entries, isEmpty);
      expect(harness.library.findById('prefs')!.lastPosition, isNull);
    });

    testWidgets('retomar desligado ignora a posição salva',
        (tester) async {
      final harness = _Harness();
      await harness.preferences.update(harness.preferences.current
          .copyWith(resumeAutomatically: false));
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
              lastPosition: const Duration(minutes: 5),
              duration: const Duration(minutes: 10)));

      expect(harness.player.session.position, Duration.zero);
    });

    testWidgets('retomar ligado volta à posição salva', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
              lastPosition: const Duration(minutes: 5),
              duration: const Duration(minutes: 10)));

      expect(harness.player.session.position,
          const Duration(minutes: 5));
    });

    testWidgets('autoplay ligado inicia sozinho', (tester) async {
      final harness = _Harness();
      await harness.preferences
          .update(harness.preferences.current.copyWith(autoplay: true));
      await harness.pump(tester);
      await _openPlayer(tester, harness, _item());

      expect(harness.player.session.status, PlaybackStatus.playing);
    });

    testWidgets('sem autoplay aguarda o usuário', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await _openPlayer(tester, harness, _item());

      expect(
          harness.player.session.status, isNot(PlaybackStatus.playing));
    });
  });

  group('próximo item', () {
    Future<void> setup(WidgetTester tester, _Harness harness) async {
      await harness.library.upsert(_item(id: 'a', title: 'Vídeo A'));
      await harness.library.upsert(_item(
          id: 'b',
          title: 'Vídeo B',
          source: 'https://exemplo.com/b.mp4',
          duration: const Duration(minutes: 5)));
      await harness.history.record(HistoryEntry(
        mediaId: 'b',
        accessedAt: DateTime(2026, 2, 2),
        position: const Duration(seconds: 42),
        completed: false,
      ));
      await harness.pump(tester);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player,
          arguments: harness.library.findById('a'));
      await tester.pumpAndSettle();
    }

    testWidgets('fim mostra o próximo e avança com a posição',
        (tester) async {
      final harness = _Harness();
      await setup(tester, harness);

      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();
      expect(find.text('A seguir: Vídeo B'), findsOneWidget);

      await tester.tap(find.widgetWithText(FocusableButton, 'Próximo'));
      await tester.pumpAndSettle();
      expect(find.text('Vídeo B'), findsOneWidget);
      expect(harness.player.session.position,
          const Duration(seconds: 42));
    });

    testWidgets('reproduzir próximo avança sozinho', (tester) async {
      final harness = _Harness();
      await harness.preferences.update(
          harness.preferences.current.copyWith(autoplayNext: true));
      await setup(tester, harness);

      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();
      expect(find.text('Reprodução concluída'), findsNothing);
      expect(find.text('Vídeo B'), findsOneWidget);
    });
  });

  group('ações de erro', () {
    testWidgets('erro em link oferece editar com endereço preenchido',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      const url = 'https://exemplo.com/quebrado.mp4';
      await _openPlayer(tester, harness, _item(source: url));

      harness.player.simulateStatus(PlaybackStatus.error);
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar este link. Verifique '
          'a conexão ou confirme se o endereço ainda está disponível.'),
          findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Editar link'),
          findsOneWidget);

      await tester
          .tap(find.widgetWithText(FocusableButton, 'Editar link'));
      await tester.pumpAndSettle();
      expect(find.text('Carregar link'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, url);
    });

    testWidgets('erro local oferece localizar, remover e fechar',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await _openPlayer(
          tester, harness, _item(source: r'C:\videos\quebrado.mp4'));

      harness.player.simulateStatus(PlaybackStatus.error);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FocusableButton, 'Tentar novamente'),
          findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Localizar arquivo…'),
          findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Remover da biblioteca'),
          findsOneWidget);

      await tester.tap(
          find.widgetWithText(FocusableButton, 'Remover da biblioteca'));
      await tester.pumpAndSettle();
      // F3 (Fase 4b): pede confirmação antes de remover.
      expect(find.text('Remover da biblioteca?'), findsOneWidget);
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsNothing);
    });

    testWidgets('saída com erro preserva a retomada salva',
        (tester) async {
      final harness = _Harness();
      await harness.history.record(HistoryEntry(
        mediaId: 'prefs',
        accessedAt: DateTime(2026, 3, 3),
        position: const Duration(minutes: 5),
        completed: false,
      ));
      await harness.pump(tester);
      await _openPlayer(
          tester,
          harness,
          _item(
              lastPosition: const Duration(minutes: 5),
              duration: const Duration(minutes: 10)));

      // Modela a abertura falhada da TV (arquivo ausente): nada
      // carregado - posicao zero, sem duracao, com erro.
      await harness.player.stop();
      await tester.pump();
      harness.player.simulateStatus(PlaybackStatus.error);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(harness.history.entries.single.position,
          const Duration(minutes: 5));
      expect(harness.library.findById('prefs')!.lastPosition,
          const Duration(minutes: 5));
    });
  });
}
