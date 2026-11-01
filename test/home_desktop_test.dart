import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/media_card.dart';

/// T7: Início no desktop com fileiras; celular e TV presos na lista
/// vertical de antes. Segue o idioma de small_window_test (superfície
/// + MediaQuery pela view, takeException para estouro).
class _Harness {
  _Harness({this.mobile = false})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(
        preferences.current.copyWith(showOnboarding: false));
  }

  final bool mobile;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player = const NoOpMediaPlayerService();
  final NoOpWindowService windows = NoOpWindowService();
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

MediaItem video(
  String id, {
  MediaSourceType type = MediaSourceType.url,
  bool favorite = false,
}) =>
    MediaItem(
      id: id,
      title: 'Vídeo $id',
      sourceType: type,
      source: type == MediaSourceType.local
          ? '/videos/$id.mp4'
          : 'https://exemplo.com/$id.mp4',
      duration: const Duration(minutes: 10),
      addedAt: DateTime(2026, 1, 1),
      isFavorite: favorite,
    );

Future<void> _seedResume(_Harness harness) async {
  for (final id in const ['1', '2', '3']) {
    await harness.library.upsert(video(id));
    await harness.history.record(HistoryEntry(
      mediaId: id,
      accessedAt: DateTime(2026, 1, 2),
      position: const Duration(seconds: 10),
    ));
  }
}

Future<_Harness> _boot(
  WidgetTester tester,
  Size size, {
  bool mobile = false,
  bool tvMode = false,
  bool manualSafeMode = false,
  List<MainDestination> hidden = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final harness = _Harness(mobile: mobile);
  await harness.preferences.update(harness.preferences.current.copyWith(
    showOnboarding: false,
    tvMode: tvMode,
    hiddenDestinations: hidden,
  ));
  if (manualSafeMode) await harness.guard.setManualSafeMode(true);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

Finder get _horizontalRows => find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );

void main() {
  group('fileiras no desktop', () {
    testWidgets('3440x1440 usa a largura toda com 3 fileiras',
        (tester) async {
      final harness = await _boot(tester, const Size(3440, 1440));
      await harness.library.upsert(video('r'));
      await harness.history.record(HistoryEntry(
        mediaId: 'r',
        accessedAt: DateTime(2026, 1, 2),
        position: const Duration(seconds: 10),
      ));
      for (var i = 0; i < 15; i++) {
        await harness.library.upsert(video(
          'l$i',
          type: MediaSourceType.local,
        ));
      }
      await harness.library.upsert(video('f', favorite: true));
      await tester.pumpAndSettle();

      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(find.text('Arquivos locais'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(_horizontalRows, findsNWidgets(3));
      expect(tester.getRect(_horizontalRows.first).width, greaterThan(3000));
      // Pôster sem aumentar: o cartão mantém a largura de sempre e a
      // janela cheia mostra bem mais cartão que o 1080 de antes.
      final cards = find.byType(MediaCard);
      expect(tester.getRect(cards.first).width, 320);
      var inWindow = 0;
      for (var i = 0; i < tester.widgetList(cards).length; i++) {
        if (tester.getRect(cards.at(i)).right <= 3440) inWindow++;
      }
      expect(inWindow, greaterThan(5));
      expect(find.text('Abrir arquivo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('janela pequena não estoura', (tester) async {
      final harness = await _boot(tester, const Size(464, 231));
      await _seedResume(harness);
      await harness.library.upsert(video('l', type: MediaSourceType.local));
      await tester.pumpAndSettle();

      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('setas movem o foco e Enter abre o item', (tester) async {
      final harness = await _boot(tester, const Size(1280, 800));
      await _seedResume(harness);
      await tester.pumpAndSettle();

      // Corpo do cartão 1 -> menu do cartão 1 -> corpo do cartão 2.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Vídeo 2'), findsOneWidget);

      // Sai do player: o teste termina no Início, sem timer pendente.
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Continuar assistindo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('posição volta depois do player', (tester) async {
      final harness = await _boot(tester, const Size(1280, 800));
      for (var i = 1; i <= 15; i++) {
        final id = '$i';
        await harness.library.upsert(video(id));
        await harness.history.record(HistoryEntry(
          mediaId: id,
          accessedAt: DateTime(2026, 1, 2),
          position: const Duration(seconds: 10),
        ));
      }
      await tester.pumpAndSettle();

      // Rola a fileira (o Continuar assistindo mostra 10: a fileira
      // estoura a janela) e fixa o deslocamento em pixels.
      await tester.drag(_horizontalRows.first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      double offset() => tester
          .state<ScrollableState>(
            find.descendant(
              of: _horizontalRows.first,
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels;
      final before = offset();
      expect(before, greaterThan(0));

      // Abre um cartão visível e volta: o deslocamento fica onde
      // estava (o conteúdo pode reordenar: o assistido vai à frente).
      await tester.tap(find.text('Vídeo 3'));
      await tester.pumpAndSettle();
      expect(find.text('Vídeo 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(offset(), before);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('tela atual presa em TV e celular', () {
    testWidgets('TV mantém a lista vertical', (tester) async {
      final harness =
          await _boot(tester, const Size(960, 540), tvMode: true);
      await _seedResume(harness);
      await tester.pumpAndSettle();

      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(find.byType(MediaCard), findsWidgets);
      expect(_horizontalRows, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('celular mantém lista e abas', (tester) async {
      final harness =
          await _boot(tester, const Size(390, 844), mobile: true);
      await _seedResume(harness);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(_horizontalRows, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('vazio, destinos e modo seguro', () {
    testWidgets('vazio mostra as ações de abertura', (tester) async {
      await _boot(tester, const Size(1280, 800));

      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
      expect(find.text('Abrir arquivo'), findsOneWidget);
      expect(find.text('Abrir link'), findsOneWidget);
    });

    testWidgets('destino escondido some do Início', (tester) async {
      await _boot(
        tester,
        const Size(1280, 800),
        hidden: const [MainDestination.library],
      );

      expect(find.byTooltip('Biblioteca'), findsNothing);
      expect(find.byTooltip('Add-ons'), findsOneWidget);
    });

    testWidgets('faixa de modo seguro continua no Início', (tester) async {
      await _boot(
        tester,
        const Size(1280, 800),
        manualSafeMode: true,
      );

      expect(find.textContaining('Modo seguro ativado manualmente'),
          findsOneWidget);
    });

    testWidgets('outras telas seguem em 1080', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: AppShell(title: 't', body: Text('x')),
      ));
      await tester.pumpAndSettle();

      final box = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.text('x'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxWidth, 1080);
    });
  });
}
