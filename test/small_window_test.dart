import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/player_controls.dart';

/// Janela pequena e minimizada no Windows (assistir enquanto trabalha).
/// 464x231 e a area cliente da janela compacta 480x270 (barra de titulo
/// e bordas do Windows descontadas).
const _compactClient = Size(464, 231);

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
  }

  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final player = const NoOpMediaPlayerService();
  final windows = NoOpWindowService();
  final LocalAddonService addons;
  final StartupGuard guard;

  Widget get app => PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: windows,
        addonService: addons,
        startupGuard: guard,
        diagnosticsService: DiagnosticsService(
          store: InMemoryLocalStore(),
          preferences: preferences,
          library: library,
          history: history,
          player: player,
          addons: addons,
          guard: guard,
        ),
      );
}

final _item = MediaItem(
  id: 'janela',
  title: 'Um título de vídeo bem comprido para a janela pequena',
  sourceType: MediaSourceType.url,
  source: 'https://exemplo.com/v.mp4',
  addedAt: DateTime(2026, 1, 1),
);

Future<_Harness> _boot(WidgetTester tester, Size size) async {
  // Tamanho da view (nao so da superficie): o MediaQuery tambem segue.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final harness = _Harness();
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _push(WidgetTester tester, String route,
    [Object? arguments]) async {
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(route, arguments: arguments);
  await tester.pumpAndSettle();
}

Future<void> _openPlayer(WidgetTester tester, _Harness harness) async {
  await harness.library.upsert(_item);
  await _push(tester, AppRoutes.player, _item);
}

void main() {
  test('janela minima e a do compacto', () {
    expect(WindowManagerService.minimumSize, WindowManagerService.compactSize);
    expect(WindowManagerService.compactSize, const Size(480, 270));
  });

  group('menus na janela compacta nao estouram', () {
    for (final route in const [
      AppRoutes.home,
      AppRoutes.library,
      AppRoutes.favorites,
      AppRoutes.history,
      AppRoutes.settings,
      AppRoutes.openMedia,
      AppRoutes.addons,
      AppRoutes.addonRepos,
      AppRoutes.addonUpdates,
      AppRoutes.diagnostics,
      AppRoutes.onboarding,
    ]) {
      testWidgets(route, (tester) async {
        await _boot(tester, _compactClient);
        if (route != AppRoutes.home) await _push(tester, route);
        // Estouro de RenderFlex vira excecao no teste.
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('player na janela pequena', () {
    testWidgets('card de uma fileira, legivel e longe dos cantos',
        (tester) async {
      final harness = await _boot(tester, _compactClient);
      await _openPlayer(tester, harness);
      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(BackdropFilter));
      final corner = tester.getRect(find.byTooltip('Fechar'));
      // Uma fileira: ~52 de altura, abaixo dos cantos, dentro da tela.
      expect(card.height, lessThanOrEqualTo(56));
      expect(card.top, greaterThan(corner.bottom + 100));
      expect(card.bottom, lessThanOrEqualTo(_compactClient.height));
      // Sem titulo nem trilho de volume; progresso e acoes ficam.
      expect(find.text(_item.title), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
      for (final tip in const [
        'Silenciar',
        'Retroceder 10 segundos',
        'Reproduzir',
        'Avançar 10 segundos',
        'Configurações',
        'Tela cheia',
        'Modo compacto',
        'Fechar',
      ]) {
        final rect = tester.getRect(find.byTooltip(tip));
        expect(rect.size, const Size(36, 36), reason: tip);
        expect(rect.left, greaterThanOrEqualTo(0), reason: tip);
        expect(rect.right, lessThanOrEqualTo(_compactClient.width),
            reason: tip);
      }
      // Progresso com largura util para arrastar.
      expect(tester.getSize(find.byType(Slider)).width,
          greaterThanOrEqualTo(120));
    });

    testWidgets('painel de configuracoes abre sem estouro', (tester) async {
      final harness = await _boot(tester, _compactClient);
      await _openPlayer(tester, harness);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // O topo do painel fica dentro da janela (antes saia pelo topo).
      expect(tester.getRect(find.text('Idioma')).top,
          greaterThanOrEqualTo(0));
    });

    testWidgets('640x360 tambem usa a fileira unica', (tester) async {
      final harness = await _boot(tester, const Size(640, 360));
      await _openPlayer(tester, harness);
      expect(tester.takeException(), isNull);
      expect(
          tester.getSize(find.byType(BackdropFilter)).height,
          lessThanOrEqualTo(56));
    });

    testWidgets('acima do limite o card do desktop nao muda',
        (tester) async {
      final harness = await _boot(
          tester, const Size(1264, PlayerControls.denseMaxHeight));
      await _openPlayer(tester, harness);
      final card = tester.getRect(find.byType(BackdropFilter));
      // Mesmo desenho de antes, sem trilho de volume: titulo, mudo
      // e progresso, botoes de 44.
      expect(find.text(_item.title), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Silenciar'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Fechar')), const Size(44, 44));
      expect(card.width, 880);
      expect(card.bottom, PlayerControls.denseMaxHeight - 16);
    });
  });

  // Regressao: entrar/sair do compacto troca o card (fileira unica <->
  // normal) com o foco dentro dele; o anel do slider novo subia os
  // ancestrais do elemento em desativacao (assert, tela vermelha ao
  // fechar o player no Windows).
  testWidgets('compacto, minimizar, sair e fechar sem erro', (tester) async {
    final harness = await _boot(tester, const Size(1264, 681));
    await _openPlayer(tester, harness);
    await tester.tap(find.byTooltip('Modo compacto'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = _compactClient;
    await tester.pumpAndSettle();
    harness.windows.simulateMinimize();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sair do modo compacto'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(2752, 1081);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Continuar assistindo'), findsOneWidget);
  });

  group('fechar pelo X do Windows', () {
    testWidgets('grava a posicao antes de a janela fechar', (tester) async {
      final harness = await _boot(tester, const Size(1264, 681));
      await _openPlayer(tester, harness);
      expect(harness.history.entries, isEmpty);

      await harness.windows.simulateClose();
      await tester.pumpAndSettle();

      expect(harness.history.entries, hasLength(1));
      expect(harness.history.entries.single.mediaId, _item.id);
    });

    testWidgets('fora do player o X nao grava nada', (tester) async {
      final harness = await _boot(tester, const Size(1264, 681));
      await _openPlayer(tester, harness);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      final saved = harness.history.entries.single.accessedAt;

      // O player saiu: a tarefa dele foi removida (nenhuma gravacao nova).
      await harness.windows.simulateClose();
      await tester.pumpAndSettle();
      expect(harness.history.entries.single.accessedAt, saved);
    });
  });

  group('minimizar', () {
    testWidgets('janela minimizada grava a posicao e segue no player',
        (tester) async {
      final harness = await _boot(tester, const Size(1264, 681));
      await _openPlayer(tester, harness);
      expect(harness.history.entries, isEmpty);

      // Windows: o window_manager avisa o minimizar.
      harness.windows.simulateMinimize();
      await tester.pumpAndSettle();

      expect(harness.history.entries, hasLength(1));
      expect(harness.history.entries.single.mediaId, _item.id);
      expect(find.byType(PlayerControls), findsOneWidget);
    });

    testWidgets('app oculto grava a posicao e segue no player',
        (tester) async {
      final harness = await _boot(tester, const Size(1264, 681));
      await _openPlayer(tester, harness);
      expect(harness.history.entries, isEmpty);

      // Windows reporta a janela minimizada como `hidden`.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpAndSettle();

      expect(harness.history.entries, hasLength(1));
      expect(harness.history.entries.single.mediaId, _item.id);

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // Restaurou no mesmo video, com os controles.
      expect(find.byType(PlayerControls), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);
    });
  });
}
