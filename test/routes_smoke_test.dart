import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/models/media_item.dart';
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
      );
}

void main() {
  group('rotas', () {
    testWidgets('inicial vazia oferece abrir arquivo e link',
        (tester) async {
      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
      expect(
          find.widgetWithText(FocusableButton, 'Abrir arquivo'),
          findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Abrir link'),
          findsOneWidget);
    });

    testWidgets('navega por biblioteca, favoritos, historico e ajustes',
        (tester) async {
      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();

      for (final target in [
        ('Biblioteca', 'Biblioteca vazia'),
        ('Favoritos', 'Sem favoritos'),
        ('Histórico', 'Histórico vazio'),
        ('Configurações', 'Aparência'),
      ]) {
        await tester.tap(find.byTooltip(target.$1));
        await tester.pumpAndSettle();
        expect(find.text(target.$2), findsOneWidget,
            reason: 'tela ${target.$1}');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
    });

    testWidgets('abrir link invalido mostra erro de validacao',
        (tester) async {
      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();

      await tester
          .tap(find.widgetWithText(FocusableButton, 'Abrir link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'nao e url');
      await tester.tap(find.widgetWithText(FocusableButton, 'Carregar link'));
      await tester.pumpAndSettle();

      expect(find.text('Esse endereço não parece um link válido.'),
          findsOneWidget);
    });

    testWidgets('abrir arquivo chega ao player e salva ao sair',
        (tester) async {
      // F8-runtime: player local pede acesso antes de abrir; mock
      // concede de imediato (sem ele, o tap em Reproduzir corre
      // antes do open e o play cai em idle).
      const permChannel = MethodChannel('player/media_permission');
      final messenger = TestWidgetsFlutterBinding
          .ensureInitialized()
          .defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          permChannel, (call) async => 'granted');
      addTearDown(
          () => messenger.setMockMethodCallHandler(permChannel, null));
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester
          .tap(find.widgetWithText(FocusableButton, 'Abrir arquivo'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).first, r'C:\videos\teste.mp4');
      await tester
          .tap(find.widgetWithText(FocusableButton, 'Abrir arquivo'));
      await tester.pumpAndSettle();

      // Player aberto com o titulo derivado do caminho.
      expect(find.text('teste'), findsOneWidget);
      expect(find.byTooltip('Reproduzir'), findsOneWidget);

      // Play/pause alterna o rotulo.
      await tester.tap(find.byTooltip('Reproduzir'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pausar'), findsOneWidget);

      // Painel de configuracoes abre e fecha sem travar.
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsOneWidget);

      // Submenu de idioma abre e volta a lista principal.
      await tester.tap(find.text('Idioma'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma faixa disponível'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      // Sair pelo voltar salva a sessao no historico.
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
      expect(harness.library.items, hasLength(1));
    });

    testWidgets('player direto por rota exibe a midia', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final item = MediaItem(
        id: 'direto',
        title: 'Vídeo direto',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/v.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      await harness.library.upsert(item);

      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
      await tester.pumpAndSettle();

      expect(find.text('Vídeo direto'), findsOneWidget);
    });
  });

  group('matriz de reprodução (§22, §26.10)', () {
    Future<_Harness> openWithDuration(
        WidgetTester tester, Duration duration) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      final item = MediaItem(
        id: 'matriz',
        title: 'Matriz',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/m.mp4',
        duration: duration,
        addedAt: DateTime(2026, 1, 1),
      );
      await harness.library.upsert(item);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('avançar e retroceder movem 10 segundos', (tester) async {
      final harness =
          await openWithDuration(tester, const Duration(minutes: 10));

      await tester.tap(find.byTooltip('Avançar 10 segundos'));
      await tester.pumpAndSettle();
      expect(harness.player.session.position,
          const Duration(seconds: 10));

      await tester.tap(find.byTooltip('Retroceder 10 segundos'));
      await tester.pumpAndSettle();
      expect(
          harness.player.session.position, Duration.zero);
    });

    testWidgets('barra de progresso responde ao arrasto', (tester) async {
      final harness =
          await openWithDuration(tester, const Duration(minutes: 10));

      // Primeiro slider dos controles: o progresso (o segundo e o
      // volume). Arrastar para a direita avança a posição.
      final progress = find.byType(Slider).first;
      expect(tester.widget<Slider>(progress).max, greaterThan(1));
      await tester.drag(progress, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(harness.player.session.position, greaterThan(Duration.zero));
    });

    testWidgets('velocidade indicada e aplicada', (tester) async {
      final harness =
          await openWithDuration(tester, const Duration(minutes: 10));

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1,5x'));
      await tester.pumpAndSettle();

      expect(harness.player.session.speed, 1.5);
      // A indicada resolve cor de destaque; as demais, transparente.
      Color? fillOf(String label) =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, label))
              .style?.backgroundColor
              ?.resolve(const <WidgetState>{});
      expect(fillOf('1,5x'), isNot(Colors.transparent));
      expect(fillOf('1,0x'), Colors.transparent);

      // Higiene: a sessão em memória é compartilhada entre testes.
      await tester.tap(find.text('1,0x'));
      await tester.pumpAndSettle();
    });

    testWidgets('modo compacto alterna no desktop', (tester) async {
      final harness =
          await openWithDuration(tester, const Duration(minutes: 10));

      await tester.tap(find.byTooltip('Modo compacto'));
      await tester.pumpAndSettle();
      expect(await harness.windows.isCompact, isTrue);
      expect(find.byTooltip('Sair do modo compacto'), findsOneWidget);

      await tester.tap(find.byTooltip('Sair do modo compacto'));
      await tester.pumpAndSettle();
      expect(await harness.windows.isCompact, isFalse);
      expect(find.byTooltip('Modo compacto'), findsOneWidget);
    });

    testWidgets('ultrawide mantém a inicial utilizável', (tester) async {
      tester.view.physicalSize = const Size(2560, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();

      // Estouro de layout reprova sozinho; o conteúdo segue alcançável.
      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Abrir arquivo'),
          findsOneWidget);
      expect(find.widgetWithText(FocusableButton, 'Abrir link'),
          findsOneWidget);
    });

    testWidgets('curta e longa abrem com limites coerentes',
        (tester) async {
      final harness =
          await openWithDuration(tester, const Duration(seconds: 30));
      expect(find.text('0:30'), findsOneWidget);

      // Busca além do fim limita na duração.
      await harness.player.seek(const Duration(minutes: 10));
      await tester.pump();
      expect(harness.player.session.position,
          const Duration(seconds: 30));

      // Longa: rótulo de horas e busca distante funcionam.
      final long = MediaItem(
        id: 'longa',
        title: 'Longa',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/l.mp4',
        duration: const Duration(hours: 3),
        addedAt: DateTime(2026, 1, 1),
      );
      await harness.library.upsert(long);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.player, arguments: long);
      await tester.pumpAndSettle();

      expect(find.text('3:00:00'), findsOneWidget);
      await harness.player.seek(const Duration(hours: 2));
      await tester.pump();
      expect(harness.player.session.position,
          const Duration(hours: 2));
    });
  });
}
