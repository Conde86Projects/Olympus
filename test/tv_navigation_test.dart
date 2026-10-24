import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/media_card.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/slider_focus_ring.dart';

class _Harness {
  _Harness()
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
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

/// Tooltip do botão com foco agora (D-pad/OK navegam por foco; saber
/// onde ele está é o coração da spec 18).
String? _focusedTooltip() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<Tooltip>()?.message;
}

/// true quando o foco está dentro do escopo da barra de controles.
bool _focusInControlsScope() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return false;
  return node.ancestors.any((a) => a.debugLabel == 'controls');
}

/// Rótulo do botão do overlay com foco (os `.icon` guardam o texto
/// como descendente). Null quando o foco está fora dos botões do
/// overlay (cantos) — e nunca no nó da tela (F2 pula ele).
String? _focusedOverlayLabel(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final button = context.findAncestorWidgetOfExactType<FilledButton>() ??
      context.findAncestorWidgetOfExactType<OutlinedButton>();
  if (button == null) return null;
  final texts = find.descendant(
    of: find.byWidget(button),
    matching: find.byType(Text),
  );
  if (texts.evaluate().isEmpty) return null;
  return (texts.evaluate().first.widget as Text).data;
}

/// O foco atual está num botão visível e acionável: nunca no nó da
/// tela (armadilha F2) nem num controle oculto pela barra escondida.
void _expectFocusVisible(WidgetTester tester, String reason) {
  final context = FocusManager.instance.primaryFocus?.context;
  expect(context, isNotNull, reason: reason);
  var buttonFound = false;
  var hidden = false;
  context!.visitAncestorElements((e) {
    final w = e.widget;
    if (w is FilledButton || w is OutlinedButton || w is IconButton) {
      buttonFound = true;
    }
    if ((w is Offstage && w.offstage) || (w is Visibility && !w.visible)) {
      hidden = true;
    }
    return true;
  });
  expect(buttonFound, isTrue, reason: '$reason (foco num botão)');
  expect(hidden, isFalse, reason: '$reason (botão visível, não oculto)');
}

/// Rótulo do botão de diálogo com foco (TextButton/FilledButton).
String? _focusedDialogLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final text = context.findAncestorWidgetOfExactType<TextButton>();
  if (text != null) return (text.child as Text).data;
  final filled = context.findAncestorWidgetOfExactType<FilledButton>();
  if (filled != null) return (filled.child as Text).data;
  return null;
}

Future<_Harness> _openPlayer(
  WidgetTester tester, {
  String id = 'tv',
  bool tvMode = false,
  bool local = false,
}) async {
  final harness = _Harness();
  if (tvMode) {
    await harness.preferences
        .update(harness.preferences.current.copyWith(tvMode: true));
  }
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: id,
    title: 'Vídeo TV',
    sourceType: local ? MediaSourceType.local : MediaSourceType.url,
    source: local ? r'C:\tv.mp4' : 'https://exemplo.com/tv.mp4',
    duration: const Duration(minutes: 10),
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  group('navegação por setas (Task 12a)', () {
    testWidgets('foco inicial cai no Reproduzir', (tester) async {
      await _openPlayer(tester);

      expect(_focusedTooltip(), 'Reproduzir');
    });

    testWidgets('setas navegam sem buscar; Enter ativa', (tester) async {
      final harness = await _openPlayer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Andou para o vizinho da direita SEM buscar a posição.
      expect(_focusedTooltip(), 'Avançar 10 segundos');
      expect(harness.player.session.position, Duration.zero);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.player.session.position, const Duration(seconds: 10));
    });

    testWidgets('seta esquerda volta e ativa retroceder', (tester) async {
      final harness = await _openPlayer(tester);
      await harness.player.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedTooltip(), 'Retroceder 10 segundos');
      expect(harness.player.session.position, const Duration(seconds: 30));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.player.session.position, const Duration(seconds: 20));
    });

    testWidgets('controles ocultos: setas buscam e reexibem', (tester) async {
      final harness = await _openPlayer(tester);

      // Deixa o auto-hide esconder a barra.
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(harness.player.session.position, const Duration(seconds: 10));
      expect(find.byTooltip('Pausar'), findsNothing);
      expect(find.byTooltip('Reproduzir'), findsOneWidget);
    });

    testWidgets('painel aberto: setas não buscam', (tester) async {
      final harness = await _openPlayer(tester);

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(harness.player.session.position, Duration.zero);
      // Segue no painel, sem efeito colateral no player.
      expect(find.text('Velocidade de reprodução'), findsOneWidget);
    });

    testWidgets('lista vazia: setas não travam', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('Nenhum add-on instalado'), findsOneWidget);
    });

    testWidgets('lista: seta desce e Enter abre o segundo', (tester) async {
      final harness = _Harness();
      for (final (id, name) in [('a.um', 'Primeiro'), ('b.dois', 'Segundo')]) {
        final json = demoManifestJson(id: id);
        json['name'] = name;
        await harness.addons.install(
          AddonManifest.fromMap(json),
          originTrusted: false,
        );
      }
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      // Primeiro item já nasce focado; descer + Enter abre o segundo.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Segundo'), findsOneWidget);
      expect(find.text('Origem'), findsOneWidget);
    });
  });

  group('foco visível e alcançabilidade (Task 12b)', () {
    testWidgets('Enter com controles ocultos reexibe sem buscar',
        (tester) async {
      final harness = await _openPlayer(tester);
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reproduzir'), findsOneWidget);
      expect(harness.player.session.position, Duration.zero);
      expect(harness.player.session.status.name, 'ready');
    });

    testWidgets('select (DPAD_CENTER) com controles ocultos reexibe',
        (tester) async {
      final harness = await _openPlayer(tester);
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reproduzir'), findsOneWidget);
      expect(harness.player.session.position, Duration.zero);
    });

    testWidgets('só teclado cancela remoção com segurança (§26.6)',
        (tester) async {
      final harness = _Harness();
      final json = demoManifestJson(id: 'demo.catalogo');
      await harness.addons.install(
        AddonManifest.fromMap(json),
        originTrusted: false,
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();

      // Primeiro cartão focado: Enter abre os detalhes.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Origem'), findsOneWidget);

      // Ativar tem o foco; a ordem e Ativar, Editar endereco,
      // Remover (destrutivo por ultimo). Duas setas chegam ao Remover.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Remover add-on?'), findsOneWidget);

      // O seguro nasce focado: OK imediato cancela, sem destruir.
      expect(_focusedDialogLabel(), 'Cancelar');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Remover add-on?'), findsNothing);
      expect(harness.addons.findById('demo.catalogo'), isNotNull);
    });

    testWidgets('biblioteca: setas + Enter abrem o item certo', (tester) async {
      final harness = _Harness();
      for (final title in ['Um', 'Dois']) {
        await harness.library.upsert(MediaItem(
          id: title,
          title: title,
          sourceType: MediaSourceType.url,
          source: 'https://exemplo.com/$title.mp4',
          addedAt: DateTime(2026, 1, 1),
        ));
      }
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Biblioteca'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Dois'), findsWidgets);
    });

    testWidgets('configurações: Tab + Enter alternam interruptor',
        (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.animations, isTrue);

      // Tab até o Animações (equivale a navegar; determinístico).
      final context = tester.element(find.byType(Scaffold).first);
      var found = false;
      for (var i = 0; i < 25 && !found; i++) {
        FocusScope.of(context).nextFocus();
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus?.context;
        final tile = focused?.findAncestorWidgetOfExactType<SwitchListTile>();
        found = tile != null && ((tile.title as Text).data == 'Animações');
      }
      expect(found, isTrue, reason: 'Animações alcançável por Tab');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.preferences.current.animations, isFalse);
    });

    test('foco tem destaque mínimo nos temas', () {
      expect(PlayerTheme.dark().focusColor.a, greaterThanOrEqualTo(0.2));
      expect(
        PlayerTheme.playerSurface(ThemeData()).focusColor.a,
        greaterThanOrEqualTo(0.2),
      );
    });
  });

  group('voltar hierárquico e foco preso (Task 13)', () {
    testWidgets('voltar do sistema sai da tela cheia sem fechar',
        (tester) async {
      await _openPlayer(tester);
      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Tela cheia'), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      expect(find.text('Vídeo TV'), findsWidgets);
    });

    testWidgets('voltar do sistema sai do cinema sem fechar', (tester) async {
      await _openPlayer(tester);
      await tester.tap(find.byTooltip('Modo cinema'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Fechar'), findsOneWidget);
      expect(find.text('Vídeo TV'), findsWidgets);
    });

    testWidgets('voltar do sistema salva e sai', (tester) async {
      final harness = await _openPlayer(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Saiu do player para a inicial (com o item em Continuar).
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
    });

    testWidgets('voltar com painel fecha só o painel', (tester) async {
      await _openPlayer(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Velocidade de reprodução'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Velocidade de reprodução'), findsNothing);
      expect(find.text('Vídeo TV'), findsWidgets);
    });

    testWidgets('foco preso no diálogo de remoção', (tester) async {
      final harness = _Harness();
      final json = demoManifestJson(id: 'demo.catalogo');
      await harness.addons.install(
        AddonManifest.fromMap(json),
        originTrusted: false,
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add-ons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo Demo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Remover add-on?'), findsOneWidget);

      // Tab circula só entre Cancelar e Remover, sem vazar para trás.
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final context = FocusManager.instance.primaryFocus?.context;
        expect(
          context?.findAncestorWidgetOfExactType<AlertDialog>(),
          isNotNull,
          reason: 'Tab ${i + 1} mantém o foco no diálogo',
        );
      }
      expect(_focusedDialogLabel(), isIn(['Cancelar', 'Remover']));
    });

    testWidgets('foco preso no painel do player', (tester) async {
      await _openPlayer(tester);
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final context = FocusManager.instance.primaryFocus?.context;
        expect(
          context?.findAncestorWidgetOfExactType<PlayerSettingsPanel>(),
          isNotNull,
          reason: 'Tab ${i + 1} mantém o foco no painel',
        );
      }
    });
  });

  group('overlays de erro/fim: foco preso nos botões (F2)', () {
    testWidgets('erro: autofocus no Tentar e setas percorrem sem escapar',
        (tester) async {
      final harness = await _openPlayer(tester);
      harness.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();

      expect(_focusedOverlayLabel(tester), 'Tentar novamente');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Editar link');
      // Editar e Fechar dividem a linha: lateral anda, baixo fica.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Fechar');
      // No último botão: descer não escapa para o nó da tela.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Fechar');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Editar link');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Tentar novamente');
      // Acima do primeiro: cantos visíveis (com tooltip), nunca o vazio.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), isNull);
      expect(_focusedTooltip(), isNotNull);
    });

    testWidgets('erro: timer de hide não rouba o foco do overlay',
        (tester) async {
      final harness = await _openPlayer(tester);
      harness.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Tentar novamente');

      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Tentar novamente');
    });

    testWidgets('retry após erro reexibe os controles', (tester) async {
      final harness = await _openPlayer(tester);
      harness.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();
      // Deixa o hide esconder o estado da barra sob o overlay.
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tentar novamente'));
      harness.player.simulateStatus(PlaybackStatus.playing);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pausar'), findsOneWidget);
    });

    testWidgets('concluído após hide foca o Reproduzir (sem travar)',
        (tester) async {
      final harness = await _openPlayer(tester);
      // Esconde a barra: foco ancora no nó da tela.
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();
      expect(_focusedOverlayLabel(tester), 'Reproduzir novamente');
    });

    testWidgets('concluído: setas percorrem sem cair no texto', (tester) async {
      final harness = await _openPlayer(tester);
      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();

      expect(_focusedOverlayLabel(tester), 'Reproduzir novamente');
      final arrows = [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
      ];
      for (var i = 0; i < arrows.length; i++) {
        await tester.sendKeyEvent(arrows[i]);
        await tester.pumpAndSettle();
        _expectFocusVisible(tester, 'seta $i não cai no vazio nem no oculto');
      }
    });

    testWidgets('concluído na TV: card sólido compacto, sem transparência',
        (tester) async {
      final harness = await _openPlayer(tester, tvMode: true);
      harness.player.simulateStatus(PlaybackStatus.completed);
      await tester.pumpAndSettle();

      expect(find.text('Reprodução concluída'), findsOneWidget);
      final card = tester.widget<Container>(find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                PlayerSettingsPanel.panelColor,
      ));
      expect((card.decoration as BoxDecoration).color!.a, 1.0);
      final title =
          tester.widget<Text>(find.text('Reprodução concluída'));
      expect(title.style!.fontSize, 17);
      final wrap = tester.widget<Wrap>(find
          .ancestor(
            of: find.text('Reproduzir novamente'),
            matching: find.byType(Wrap),
          )
          .first);
      expect(wrap.spacing, 8);
      expect(wrap.runSpacing, 8);
    });
  });

  group('remoção de mídia pede confirmação (F3)', () {
    Future<_Harness> libraryWithOne(WidgetTester tester) async {
      final harness = _Harness();
      await harness.library.upsert(MediaItem(
        id: 'filme',
        title: 'Filme',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/filme.mp4',
        addedAt: DateTime(2026, 1, 1),
      ));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Biblioteca'));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('biblioteca: OK no Remover pede confirmação e cancela',
        (tester) async {
      final harness = await libraryWithOne(tester);
      await tester.tap(find.byTooltip('Opções'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Remover da biblioteca?'), findsOneWidget);

      // Cancelar nasce focado (§26.6): OK imediato cancela.
      expect(_focusedDialogLabel(), 'Cancelar');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Remover da biblioteca?'), findsNothing);
      expect(harness.library.findById('filme'), isNotNull);
    });

    testWidgets('biblioteca: confirmar remove e cascata o histórico',
        (tester) async {
      final harness = await libraryWithOne(tester);
      await harness.history.record(HistoryEntry(
        mediaId: 'filme',
        accessedAt: DateTime(2026, 1, 2),
        position: const Duration(seconds: 10),
        percentWatched: 0.1,
        completed: false,
      ));
      await tester.tap(find.byTooltip('Opções'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remover').last);
      await tester.pumpAndSettle();
      expect(harness.library.findById('filme'), isNull);
      expect(harness.history.latestFor('filme'), isNull);
    });

    testWidgets('player: Remover da biblioteca pede confirmação e cancela',
        (tester) async {
      final harness = await _openPlayer(tester, local: true);
      harness.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remover da biblioteca'));
      await tester.pumpAndSettle();
      expect(find.text('Remover da biblioteca?'), findsOneWidget);
      expect(_focusedDialogLabel(), 'Cancelar');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Remover da biblioteca?'), findsNothing);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(harness.library.findById('tv'), isNotNull);
    });

    testWidgets('histórico: confirmar tira do histórico e mantém o item',
        (tester) async {
      final harness = _Harness();
      await harness.library.upsert(MediaItem(
        id: 'filme',
        title: 'Filme',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/filme.mp4',
        addedAt: DateTime(2026, 1, 1),
      ));
      await harness.history.record(HistoryEntry(
        mediaId: 'filme',
        accessedAt: DateTime(2026, 1, 2),
        position: const Duration(seconds: 10),
        percentWatched: 0.1,
        completed: false,
      ));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Histórico'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Opções'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Remover do histórico?'), findsOneWidget);

      await tester.tap(find.text('Remover').last);
      await tester.pumpAndSettle();
      expect(harness.history.latestFor('filme'), isNull);
      expect(harness.library.findById('filme'), isNotNull);
    });
  });

  group('modo TV (Task 14)', () {
    test('prefs persistem o modo TV', () {
      const prefs = UserPreferences();
      expect(prefs.tvMode, isFalse);
      final on = prefs.copyWith(tvMode: true);
      expect(
        UserPreferences.fromMap(on.toMap()).tvMode,
        isTrue,
      );
      expect(
        UserPreferences.fromMap(const {}).tvMode,
        isFalse,
      );
    });

    test('margens anti-overscan no modo TV', () {
      expect(AppShell.marginFor(800, tvMode: false), 48);
      expect(AppShell.marginFor(200, tvMode: false), 16);
      expect(AppShell.marginFor(200, tvMode: true), 32);
      expect(AppShell.marginFor(2000, tvMode: true), 96);
    });

    testWidgets('botões usam o alvo mínimo em cada modo', (tester) async {
      Future<double> buttonHeight(bool tvMode) async {
        final harness = _Harness();
        if (tvMode) {
          await harness.preferences
              .update(harness.preferences.current.copyWith(tvMode: true));
        }
        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();
        return tester
            .getSize(find.widgetWithText(FocusableButton, 'Abrir arquivo'))
            .height;
      }

      expect(await buttonHeight(false), 48);
      expect(await buttonHeight(true), 48);
    });

    testWidgets('texto no modo TV usa escala 1.0', (tester) async {
      final harness = _Harness();
      await harness.preferences
          .update(harness.preferences.current.copyWith(tvMode: true));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      expect(
        MediaQuery.textScalerOf(context).scale(100),
        closeTo(100, 0.01),
      );
    });

    // Spec 12.2: na TV a barra fica enquanto o usuario navega (teclas
    // chegando) e some depois de alguns segundos parado, mesmo com o
    // foco nela. Antes ela ficava para sempre (relato na TCL, 18/10).
    testWidgets('barra persiste navegando e some parada no modo TV',
        (tester) async {
      await _openPlayer(tester, tvMode: true);
      expect(_focusedTooltip(), 'Reproduzir');

      // Navegando: uma tecla a cada 3 s por 9 s, mais que o auto-hide.
      final step = AppConstants.controlsAutoHide - const Duration(seconds: 1);
      for (var i = 0; i < 3; i++) {
        await tester.pump(step);
        await tester.sendKeyEvent(
            i.isEven ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.byTooltip('Configurações'), findsOneWidget, reason: '$i');
      }

      // Parado: some.
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Configurações'), findsNothing);

      // OK reexibe e o foco volta a um controle da barra.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Configurações'), findsOneWidget);
      expect(_focusInControlsScope(), isTrue);
    });

    // Pedido do usuario (TCL, 19/10): com a barra visivel, o primeiro
    // BACK so a esconde; o segundo sai salvando.
    testWidgets('BACK na TV: primeiro esconde a barra, segundo sai',
        (tester) async {
      final harness = await _openPlayer(tester, tvMode: true);
      expect(find.byTooltip('Configurações'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Configurações'), findsNothing);
      expect(harness.history.entries, isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
    });

    testWidgets('X na TV sai direto, mesmo com a barra visivel',
        (tester) async {
      final harness = await _openPlayer(tester, tvMode: true);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
    });

    testWidgets('desktop: BACK sai direto (sem o passo da TV)',
        (tester) async {
      final harness = await _openPlayer(tester);
      expect(find.byTooltip('Configurações'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(harness.history.entries, hasLength(1));
    });

    testWidgets('subir da fileira pula o slider até os cantos',
        (tester) async {
      await _openPlayer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // Não caiu no slider: ancorou num botão dos cantos.
      expect(
        _focusedTooltip(),
        isIn([
          'Tela cheia',
          'Sair da tela cheia',
          'Modo cinema',
          'Modo compacto',
          'Adicionar aos favoritos',
          'Remover dos favoritos',
          'Fechar',
        ]),
      );
    });

    testWidgets('slider: descer alcança, laterais ajustam, Enter sai',
        (tester) async {
      final harness = await _openPlayer(tester);
      await harness.player.seek(const Duration(seconds: 60));
      await tester.pumpAndSettle();

      bool onSlider() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<Slider>() !=
          null;

      // Cantos -> descer -> slider de progresso.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusInControlsScope(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusInControlsScope(), isTrue);
      expect(onSlider(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(onSlider(), isTrue);
      expect(harness.player.session.position,
          lessThan(const Duration(seconds: 60)));

      // Enter sai para a fileira de botões, sem ajustar.
      final before = harness.player.session.position;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(onSlider(), isFalse);
      expect(harness.player.session.position, before);
      expect(
        _focusedTooltip(),
        isIn([
          'Retroceder 10 segundos',
          'Reproduzir',
          'Pausar',
          'Avançar 10 segundos',
          'Configurações',
          'Tela cheia',
          'Sair da tela cheia',
          'Ativar som',
          'Silenciar',
        ]),
      );
    });

    testWidgets('sem trilho: esquerda sai no mudo, volume intacto',
        (tester) async {
      final harness = await _openPlayer(tester);

      // Reproduzir -> esquerda, esquerda: retroceder, mudo (sem
      // trilho de volume no caminho).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedTooltip(), isIn(['Ativar som', 'Silenciar']));
      expect(harness.player.session.volume, 1.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.player.session.isMuted, isTrue);
      expect(_focusedTooltip(), 'Ativar som');
    });

    testWidgets('poke restaura o último controle, não os cantos (F5)',
        (tester) async {
      await _openPlayer(tester);

      // Sai do Pausar para marcar outro controle como último.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedTooltip(), 'Avançar 10 segundos');

      // Hide guarda o último; poke (Enter oculto) restaura nele.
      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_focusedTooltip(), 'Avançar 10 segundos');
      expect(_focusInControlsScope(), isTrue);
    });

    testWidgets('hide com foco nos cantos restaura fora dos controles (F5)',
        (tester) async {
      await _openPlayer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusInControlsScope(), isFalse);

      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Não havia controle guardado: volta para os cantos.
      expect(_focusInControlsScope(), isFalse);
      expect(
        _focusedTooltip(),
        isIn([
          'Tela cheia',
          'Sair da tela cheia',
          'Modo cinema',
          'Modo compacto',
          'Adicionar aos favoritos',
          'Remover dos favoritos',
          'Fechar',
        ]),
      );
    });

    testWidgets('telas frias nascem com foco na ação primária (F10)',
        (tester) async {
      String? focusedButtonLabel() {
        final context = FocusManager.instance.primaryFocus?.context;
        if (context == null) return null;
        final button = context.findAncestorWidgetOfExactType<FilledButton>() ??
            context.findAncestorWidgetOfExactType<OutlinedButton>();
        if (button == null) return null;
        final texts = find.descendant(
          of: find.byWidget(button),
          matching: find.byType(Text),
        );
        if (texts.evaluate().isEmpty) return null;
        return (texts.evaluate().first.widget as Text).data;
      }

      await tester.pumpWidget(_Harness().app);
      await tester.pumpAndSettle();

      // Inicial vazia: Abrir arquivo.
      expect(focusedButtonLabel(), 'Abrir arquivo');

      // Biblioteca vazia: Abrir vídeo.
      await tester.tap(find.byTooltip('Biblioteca'));
      await tester.pumpAndSettle();
      expect(focusedButtonLabel(), 'Abrir vídeo');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Configurações: primeiro controle (Tema).
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      final switchFocused = FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<Switch>() !=
          null;
      expect(switchFocused, isTrue);
    });

    testWidgets('card: RIGHT entra no Opções, LEFT volta (F7)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCard(
            item: MediaItem(
              id: 'x',
              title: 'Vídeo F7',
              sourceType: MediaSourceType.local,
              source: r'C:\f7.mp4',
              addedAt: DateTime(2026, 1, 1),
            ),
            autofocus: true,
            onTap: () {},
            onRemove: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      bool bodyFocused() {
        final ctx = FocusManager.instance.primaryFocus?.context;
        return ctx != null &&
            ctx.findAncestorWidgetOfExactType<Tooltip>() == null &&
            ctx.findAncestorWidgetOfExactType<InkWell>() != null;
      }

      bool menuFocused() {
        final ctx = FocusManager.instance.primaryFocus?.context;
        return ctx?.findAncestorWidgetOfExactType<Tooltip>()?.message ==
            'Opções';
      }

      expect(bodyFocused(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(menuFocused(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(bodyFocused(), isTrue);
    });

    testWidgets('slider focado mostra o anel (F6)', (tester) async {
      await _openPlayer(tester);

      bool ringOn() => tester
          .widgetList<Container>(find.descendant(
            of: find.byType(SliderFocusRing),
            matching: find.byType(Container),
          ))
          .any((c) =>
              ((c.decoration as BoxDecoration?)?.border as Border?)
                  ?.top
                  .color ==
              PlayerTheme.accent);

      expect(ringOn(), isFalse);

      // Cantos -> descer -> slider de progresso com anel.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(ringOn(), isTrue);
    });

    testWidgets('barra esconde ao sair dela no modo TV', (tester) async {
      await _openPlayer(tester, tvMode: true);
      expect(_focusInControlsScope(), isTrue);

      // Sobe até sair do escopo do card (slider, depois cantos).
      for (var i = 0; i < 5 && _focusInControlsScope(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
      }
      expect(_focusInControlsScope(), isFalse);

      await tester
          .pump(AppConstants.controlsAutoHide + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir'), findsNothing);
    });

    testWidgets('interruptor alterna o modo TV', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modo TV'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.tvMode, isTrue);

      await tester.tap(find.text('Modo TV'));
      await tester.pumpAndSettle();
      expect(harness.preferences.current.tvMode, isFalse);
    });
  });
}
