import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/home/mobile_shell.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_controls.dart';
import 'package:player/widgets/tv_player_controls.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Composicao de celular (MobileMode): retrato e paisagem de um
/// aparelho comum, em dp.
const _portrait = Size(390, 844);
const _landscape = Size(844, 390);

/// Grava as buscas (toque duplo).
class _SeekPlayer extends NoOpMediaPlayerService {
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await super.seek(position);
  }
}

class _Harness {
  _Harness({this.mobile = true, bool tvMode = false, bool onboarding = false})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current
        .copyWith(showOnboarding: onboarding, tvMode: tvMode));
  }

  final bool mobile;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final player = _SeekPlayer();
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
        mobilePlatform: mobile,
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
  id: 'celular',
  title: 'Vídeo no celular',
  sourceType: MediaSourceType.url,
  source: 'https://exemplo.com/v.mp4',
  addedAt: DateTime(2026, 1, 1),
);

Future<_Harness> _boot(WidgetTester tester, Size size,
    {bool mobile = true, bool tvMode = false, bool onboarding = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final harness =
      _Harness(mobile: mobile, tvMode: tvMode, onboarding: onboarding);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  group('navegacao inferior', () {
    for (final size in const [_portrait, _landscape]) {
      testWidgets('cinco abas sem estouro em $size', (tester) async {
        await _boot(tester, size);
        expect(find.byType(NavigationBar), findsOneWidget);
        for (final label in const [
          'Início',
          'Biblioteca',
          'Favoritos',
          'Add-ons',
          'Ajustes',
        ]) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final selected = tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex;
          expect(MobileShell.destinations[selected].label, label);
        }
      });
    }

    testWidgets('Inicio so mostra o Historico no topo', (tester) async {
      await _boot(tester, _portrait);
      Finder topo(String tip) => find.descendant(
          of: find.byType(AppBar), matching: find.byTooltip(tip));
      expect(topo('Histórico'), findsOneWidget);
      expect(topo('Configurações'), findsNothing);
      expect(topo('Biblioteca'), findsNothing);
    });

    testWidgets('voltar do sistema fora do Inicio volta ao Inicio',
        (tester) async {
      await _boot(tester, _portrait);
      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
          tester.widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0);
    });

    // Regressao (emulador): a rota inicial '/onboarding' deixava um
    // Inicio escondido por baixo; "Comecar" empilhava outro e as abas
    // mostravam a seta de voltar.
    testWidgets('depois da apresentacao, abas sem seta de voltar',
        (tester) async {
      await _boot(tester, _portrait, onboarding: true);
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
          Navigator.of(tester.element(find.byType(MobileShell))).canPop(),
          isFalse);
      for (final label in const ['Biblioteca', 'Add-ons', 'Ajustes']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsNothing, reason: label);
      }
    });

    testWidgets('apresentacao -> Abrir video volta ao Inicio',
        (tester) async {
      await _boot(tester, _portrait, onboarding: true);
      await tester.tap(find.text('Abrir vídeo'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir vídeo'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('alvos de toque da barra com pelo menos 48', (tester) async {
      await _boot(tester, _portrait);
      final items = find.byType(NavigationDestination);
      expect(items, findsNWidgets(MobileShell.destinations.length));
      for (final element in items.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });
  });

  // Regressao (emulador): telas abertas por cima das abas (instalar
  // add-on, detalhes, catalogo) desenhavam o fim do conteudo embaixo da
  // barra de gestos do Android.
  testWidgets('tela por cima das abas respeita a barra de gestos',
      (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 48);
    await _boot(tester, _portrait);
    final context = tester.element(find.byType(MobileShell));
    Navigator.of(context).pushNamed(AppRoutes.settings);
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(Scrollable).last);
    expect(list.bottom, lessThanOrEqualTo(_portrait.height - 48));
  });

  group('TV e desktop nao mudam', () {
    testWidgets('desktop: Home com acoes no topo, sem barra inferior',
        (tester) async {
      await _boot(tester, const Size(1280, 720), mobile: false);
      expect(find.byType(NavigationBar), findsNothing);
      for (final tip in const [
        'Biblioteca',
        'Add-ons',
        'Favoritos',
        'Histórico',
        'Configurações',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
    });

    testWidgets('Android com modo TV: sem barra inferior', (tester) async {
      await _boot(tester, const Size(960, 540), tvMode: true);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Configurações'), findsOneWidget);
    });
  });

  group('player no celular', () {
    Future<_Harness> openPlayer(WidgetTester tester, Size size,
        {bool mobile = true}) async {
      final harness = await _boot(tester, size, mobile: mobile);
      await harness.library.upsert(_item);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: _item);
      await tester.pumpAndSettle();
      return harness;
    }

    bool controlsVisible(WidgetTester tester) => tester
        .widget<Visibility>(find
            .ancestor(
                of: find.byType(PlayerControls, skipOffstage: false),
                matching: find.byType(Visibility, skipOffstage: false))
            .first)
        .visible;

    for (final size in const [_portrait, _landscape]) {
      testWidgets('botoes com 48 e sem compacto em $size', (tester) async {
        await openPlayer(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Modo compacto'), findsNothing);
        final buttons = find.byType(RoundPlayerButton);
        expect(buttons, findsWidgets);
        for (final element in buttons.evaluate()) {
          final box = tester.getRect(find.byWidget(element.widget));
          expect(box.width, greaterThanOrEqualTo(48));
          expect(box.height, greaterThanOrEqualTo(48));
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.right, lessThanOrEqualTo(size.width));
          expect(box.bottom, lessThanOrEqualTo(size.height));
        }
        // O card nao encosta nos cantos.
        final card = tester.getRect(find.byType(PlayerControls));
        final corner = tester.getRect(find.byTooltip('Fechar'));
        expect(card.top, greaterThan(corner.bottom));
      });
    }

    // Sem D-pad no celular: nunca a barra da TV (navegada por setas),
    // sempre o card de toque. Hover so existe com mouse e nao e
    // necessario: o toque alterna os controles.
    testWidgets('celular usa o card de toque, nunca a barra da TV',
        (tester) async {
      await openPlayer(tester, _portrait);
      expect(find.byType(TvPlayerControls), findsNothing);
      expect(find.byType(PlayerControls), findsOneWidget);
    });

    testWidgets('toque alterna os controles', (tester) async {
      await openPlayer(tester, _portrait);
      expect(controlsVisible(tester), isTrue);
      final center = tester.getCenter(find.byType(Stack).first);

      await tester.tapAt(center);
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(controlsVisible(tester), isFalse);

      await tester.tapAt(center);
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(controlsVisible(tester), isTrue);
    });

    testWidgets('toque duplo nas laterais busca 10 s', (tester) async {
      final harness = await openPlayer(tester, _landscape);
      Future<void> doubleTap(Offset at) async {
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 60));
      }

      await doubleTap(const Offset(150, 150));
      expect(find.text('-10 s'), findsOneWidget);
      await doubleTap(const Offset(700, 150));
      expect(find.text('+10 s'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('+10 s'), findsNothing);
      expect(harness.player.seeks,
          [const Duration(seconds: -10), const Duration(seconds: 10)]);
    });

    testWidgets('tela cheia: paisagem e barras do sistema escondidas',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await openPlayer(tester, _portrait);

      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pumpAndSettle();
      expect(
          calls.where((c) =>
              c.method == 'SystemChrome.setPreferredOrientations' &&
              (c.arguments as List).contains('DeviceOrientation.landscapeLeft')),
          isNotEmpty);
      expect(
          calls.where((c) =>
              c.method == 'SystemChrome.setEnabledSystemUIMode' &&
              c.arguments == 'SystemUiMode.immersiveSticky'),
          isNotEmpty);

      calls.clear();
      await tester.tap(find.byTooltip('Sair da tela cheia'));
      await tester.pumpAndSettle();
      expect(
          calls.where((c) =>
              c.method == 'SystemChrome.setPreferredOrientations' &&
              (c.arguments as List).isEmpty),
          isNotEmpty);
    });

    for (final mobile in const [true, false]) {
      testWidgets('cantos com fundo escuro (mobile: $mobile)',
          (tester) async {
        await openPlayer(
            tester, mobile ? _portrait : const Size(1280, 720),
            mobile: mobile);
        Color fill(String tip) => tester
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip(tip), matching: find.byType(IconButton)))
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{})!;
        // Cantos: escuro e opaco o bastante para o glifo branco
        // aparecer sobre video claro.
        for (final tip in const ['Tela cheia', 'Modo cinema', 'Fechar']) {
          final c = fill(tip);
          expect(c.computeLuminance(), lessThan(0.05), reason: tip);
          expect(c.a, greaterThanOrEqualTo(0.4), reason: tip);
        }
        // Card: sem mudanca (branco a 8%).
        expect(fill('Configurações'), Colors.white.withValues(alpha: 0.08));
      });
    }

    testWidgets('desktop: toque duplo nao busca e compacto continua',
        (tester) async {
      final harness =
          await openPlayer(tester, const Size(1280, 720), mobile: false);
      expect(find.byTooltip('Modo compacto'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Fechar')), const Size(44, 44));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(harness.player.seeks, isEmpty);
      // Clique so reexibe (nao oculta) no desktop.
      expect(controlsVisible(tester), isTrue);
    });
  });

  testWidgets('abrir o player por cima da navegacao', (tester) async {
    final harness = await _boot(tester, _portrait);
    await harness.library.upsert(_item);
    final context = tester.element(find.byType(MobileShell));
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: _item);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
