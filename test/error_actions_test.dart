import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Ticket 20: informacoes tecnicas do erro e escolha de outra fonte.
typedef _Pick = Future<String?> Function(BuildContext, {required String title});

class _Harness {
  _Harness({this.pick})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
  }

  final _Pick? pick;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
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
        pickVideo: pick,
      );
}

Future<_Harness> _open(
  WidgetTester tester, {
  required bool local,
  _Pick? pick,
  bool tv = false,
}) async {
  final harness = _Harness(pick: pick);
  if (tv) {
    await harness.preferences
        .update(harness.preferences.current.copyWith(tvMode: true));
  }
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: 'erro',
    title: 'Video com erro',
    sourceType: local ? MediaSourceType.local : MediaSourceType.url,
    source: local
        ? r'C:\Users\maria\Videos\ferias.mp4'
        : 'https://cdn.exemplo.com/pasta/video.mp4?token=segredo123',
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

String? _focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final b = ctx?.findAncestorWidgetOfExactType<FilledButton>() ??
      ctx?.findAncestorWidgetOfExactType<OutlinedButton>();
  if (b == null) return null;
  final t =
      find.descendant(of: find.byWidget(b), matching: find.byType(Text));
  if (t.evaluate().isEmpty) return null;
  return (t.evaluate().first.widget as Text).data;
}

void main() {
  group('informacoes tecnicas', () {
    testWidgets('arquivo local: mostra tipo, fonte, nome e versao sem caminho',
        (tester) async {
      final h = await _open(tester, local: true);
      h.player.simulateError(PlaybackErrorKind.source,
          r'Failed to open C:\Users\maria\Videos\ferias.mp4: not found');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver informações técnicas'));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, contains('fonte'));
      expect(text, contains('Arquivo'));
      expect(text, contains('ferias.mp4'));
      expect(text, contains(AppConstants.appVersion));
      expect(text, isNot(contains('maria')));
      expect(text, isNot(contains(r'C:\')));
    });

    testWidgets('link: mostra so o servidor, sem caminho nem token',
        (tester) async {
      final h = await _open(tester, local: false);
      h.player.simulateError(PlaybackErrorKind.network,
          'http error https://cdn.exemplo.com/pasta/video.mp4?token=segredo123 refused');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver informações técnicas'));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, contains('Link'));
      expect(text, contains('cdn.exemplo.com'));
      expect(text, isNot(contains('segredo123')));
      expect(text, isNot(contains('pasta/video')));
      expect(text, isNot(contains('https://')));
    });

    testWidgets('fecha com Voltar', (tester) async {
      final h = await _open(tester, local: true);
      h.player.simulateError(PlaybackErrorKind.decoder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver informações técnicas'));
      await tester.pumpAndSettle();
      expect(find.text('Informações técnicas'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Informações técnicas'), findsNothing);
      expect(find.text('Não foi possível reproduzir'), findsOneWidget);
    });
  });

  group('escolher outra fonte', () {
    testWidgets('arquivo local: Escolher outro vídeo troca o item',
        (tester) async {
      final h = await _open(tester,
          local: true, pick: (_, {required title}) async => r'C:\v\novo.mp4');
      h.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Escolher outro vídeo'));
      await tester.pumpAndSettle();

      expect(h.library.items.any((i) => i.source == r'C:\v\novo.mp4'), isTrue);
      expect(find.text('Não foi possível reproduzir'), findsNothing);
      expect(find.text('novo'), findsWidgets);
    });

    testWidgets('fonte ja cadastrada mantem o continuar de onde parou',
        (tester) async {
      final h = await _open(tester,
          local: true, pick: (_, {required title}) async => r'C:\v\novo.mp4');
      await h.library.upsert(MediaItem(
        id: 'antigo',
        title: 'Novo antigo',
        sourceType: MediaSourceType.local,
        source: r'C:\v\novo.mp4',
        lastPosition: const Duration(minutes: 5),
        lastPlayedAt: DateTime(2026, 2, 1),
        addedAt: DateTime(2026, 1, 1),
      ));
      h.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Escolher outro vídeo'));
      await tester.pumpAndSettle();

      final same =
          h.library.items.where((i) => i.source == r'C:\v\novo.mp4').toList();
      expect(same, hasLength(1));
      expect(same.single.id, 'antigo');
      expect(same.single.lastPosition, const Duration(minutes: 5));
      expect(same.single.lastPlayedAt, DateTime(2026, 2, 1));
    });

    testWidgets('cancelar o seletor volta ao erro', (tester) async {
      final h = await _open(tester,
          local: true, pick: (_, {required title}) async => null);
      h.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Escolher outro vídeo'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível reproduzir'), findsOneWidget);
      expect(h.library.items.length, 1);
    });

    testWidgets('link sem conexão oferece Abrir arquivo local',
        (tester) async {
      final h = await _open(tester,
          local: false, pick: (_, {required title}) async => '/sdcard/a.mp4');
      h.player.simulateError(PlaybackErrorKind.network);
      await tester.pumpAndSettle();

      expect(find.text('Escolher outro vídeo'), findsNothing);
      await tester.tap(find.text('Abrir arquivo local'));
      await tester.pumpAndSettle();
      expect(h.library.items.any((i) => i.source == '/sdcard/a.mp4'), isTrue);
    });

    testWidgets('link com outro erro nao oferece abrir arquivo local',
        (tester) async {
      final h = await _open(tester, local: false);
      h.player.simulateError(PlaybackErrorKind.source);
      await tester.pumpAndSettle();
      expect(find.text('Abrir arquivo local'), findsNothing);
      expect(find.text('Escolher outro vídeo'), findsNothing);
    });
  });

  testWidgets('TV: foco inicial, informações abrem e fecham com Voltar',
      (tester) async {
    final h = await _open(tester, local: true, tv: true);
    h.player.simulateError(PlaybackErrorKind.source);
    await tester.pumpAndSettle();

    expect(_focusedLabel(), 'Tentar novamente');
    for (var i = 0; i < 8 && _focusedLabel() != 'Ver informações técnicas'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(_focusedLabel(), 'Ver informações técnicas');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Informações técnicas'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Informações técnicas'), findsNothing);
  });
}
