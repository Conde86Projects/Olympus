import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/library/library_screen.dart';
import 'package:player/features/library/library_view.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/media_card.dart';

MediaItem _item(
  String title, {
  int addedMinutes = 0,
  int? durationMinutes,
}) =>
    MediaItem(
      id: title,
      title: title,
      sourceType: MediaSourceType.local,
      source: '/v/$title.mp4',
      addedAt: DateTime(2026, 10, 31, 12, addedMinutes),
      duration:
          durationMinutes == null ? null : Duration(minutes: durationMinutes),
    );

List<String> _titles(List<MediaItem> items) =>
    [for (final item in items) item.title];

void main() {
  group('texto de busca', () {
    test('ignora maiusculas e acentos', () {
      expect(foldForSearch('Ação ÉPICA'), 'acao epica');
      expect(foldForSearch('Pão de Açúcar'), 'pao de acucar');
    });

    test('mantem o que nao e letra acentuada', () {
      expect(foldForSearch('Filme 2 - Parte (1)'), 'filme 2 - parte (1)');
    });
  });

  group('busca', () {
    final items = [
      _item('Ação Dois', addedMinutes: 1),
      _item('acao um', addedMinutes: 2),
      _item('Zebra', addedMinutes: 3),
    ];

    test('sem texto devolve tudo', () {
      expect(libraryView(items), hasLength(3));
      expect(libraryView(items, query: '   '), hasLength(3));
    });

    test('acha sem diferenciar maiusculas e acentos', () {
      expect(_titles(libraryView(items, query: 'ACAO')),
          unorderedEquals(['Ação Dois', 'acao um']));
      expect(_titles(libraryView(items, query: 'ação')),
          unorderedEquals(['Ação Dois', 'acao um']));
    });

    test('varias palavras: todas precisam estar no titulo', () {
      expect(_titles(libraryView(items, query: 'dois acao')), ['Ação Dois']);
      expect(libraryView(items, query: 'acao zebra'), isEmpty);
    });

    test('nada encontrado devolve lista vazia', () {
      expect(libraryView(items, query: 'inexistente'), isEmpty);
    });
  });

  group('ordem', () {
    final items = [
      _item('banana', addedMinutes: 1, durationMinutes: 30),
      _item('Árvore', addedMinutes: 3),
      _item('abacaxi', addedMinutes: 2, durationMinutes: 90),
    ];

    test('recentes: o adicionado por ultimo primeiro', () {
      expect(_titles(libraryView(items, sort: LibrarySort.recent)),
          ['Árvore', 'abacaxi', 'banana']);
    });

    test('titulo: alfabetica, sem diferenciar acento e maiuscula', () {
      expect(_titles(libraryView(items, sort: LibrarySort.title)),
          ['abacaxi', 'Árvore', 'banana']);
    });

    test('duracao: mais longos primeiro, sem duracao por ultimo', () {
      expect(_titles(libraryView(items, sort: LibrarySort.duration)),
          ['abacaxi', 'banana', 'Árvore']);
    });

    test('empate segue os mais recentes', () {
      final same = [
        _item('a', addedMinutes: 1, durationMinutes: 10),
        _item('b', addedMinutes: 2, durationMinutes: 10),
      ];
      expect(_titles(libraryView(same, sort: LibrarySort.duration)),
          ['b', 'a']);
    });

    test('busca e ordem juntas', () {
      expect(
          _titles(libraryView(items,
              query: 'a', sort: LibrarySort.title)),
          ['abacaxi', 'Árvore', 'banana']);
    });
  });

  group('preferencia', () {
    test('a ordem escolhida sobrevive ao salvar e carregar', () {
      const saved = UserPreferences(librarySort: LibrarySort.duration);
      final loaded = UserPreferences.fromMap(saved.toMap());
      expect(loaded.librarySort, LibrarySort.duration);
    });

    test('padrao e recentes; valor desconhecido cai no padrao', () {
      expect(const UserPreferences().librarySort, LibrarySort.recent);
      final loaded = UserPreferences.fromMap({'librarySort': 'amanha'});
      expect(loaded.librarySort, LibrarySort.recent);
      expect(UserPreferences.fromMap(const {}).librarySort,
          LibrarySort.recent);
    });
  });

  group('tela da biblioteca', () {
    late InMemoryLibraryService library;
    late InMemoryPreferencesService preferences;

    Future<void> pumpLibrary(
      WidgetTester tester, {
      bool tv = false,
      Size size = const Size(900, 1400),
    }) async {
      library = InMemoryLibraryService();
      preferences = InMemoryPreferencesService();
      await library.upsert(_item('Ação Dois', addedMinutes: 1));
      await library.upsert(_item('Zebra', addedMinutes: 3, durationMinutes: 90));
      await library.upsert(_item('Banana', addedMinutes: 2, durationMinutes: 5));
      final history = InMemoryHistoryService();
      const player = NoOpMediaPlayerService();
      final guard = StartupGuard(InMemoryLocalStore());
      final addons = LocalAddonService(InMemoryLocalStore());
      final dependencies = AppDependencies(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: NoOpWindowService(),
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
        mobileChromeService: NoOpMobileChrome(),
      );
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(TvMode(
        enabled: tv,
        child: MaterialApp(
          home: LibraryScreen(dependencies: dependencies),
        ),
      ));
      await tester.pumpAndSettle();
    }

    List<String> shown(WidgetTester tester) => [
          for (final title in ['Ação Dois', 'Zebra', 'Banana'])
            if (find.text(title).evaluate().isNotEmpty) title,
        ]..sort((a, b) =>
            tester.getTopLeft(find.text(a)).dy
                .compareTo(tester.getTopLeft(find.text(b)).dy));

    testWidgets('comeca por recentes, com todos os itens', (tester) async {
      await pumpLibrary(tester);

      expect(shown(tester), ['Zebra', 'Banana', 'Ação Dois']);
    });

    testWidgets('digitar filtra a lista', (tester) async {
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField), 'ACAO');
      await tester.pumpAndSettle();

      expect(shown(tester), ['Ação Dois']);
    });

    testWidgets('sem resultado avisa e deixa limpar a busca', (tester) async {
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pumpAndSettle();

      expect(find.text('Nada encontrado'), findsOneWidget);
      expect(shown(tester), isEmpty);

      await tester.tap(find.text('Limpar busca'));
      await tester.pumpAndSettle();

      expect(shown(tester), hasLength(3));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('escolher a ordem reordena e fica salva', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.byType(DropdownButton<LibrarySort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Título').last);
      await tester.pumpAndSettle();

      expect(shown(tester), ['Ação Dois', 'Banana', 'Zebra']);
      expect(preferences.current.librarySort, LibrarySort.title);
    });

    testWidgets('abre ja na ordem lembrada', (tester) async {
      library = InMemoryLibraryService();
      await pumpLibrary(tester);
      await preferences.update(
          preferences.current.copyWith(librarySort: LibrarySort.duration));
      await tester.pumpAndSettle();

      expect(shown(tester), ['Zebra', 'Banana', 'Ação Dois']);
    });

    testWidgets('biblioteca vazia nao mostra busca', (tester) async {
      await pumpLibrary(tester);
      for (final item in List.of(library.items)) {
        await library.remove(item.id);
      }
      await tester.pumpAndSettle();

      expect(find.text('Biblioteca vazia'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('janela compacta nao estoura', (tester) async {
      await pumpLibrary(tester, size: const Size(480, 270));

      expect(tester.takeException(), isNull);
    });

    testWidgets('na TV o teclado so abre com OK, nao ao chegar no campo',
        (tester) async {
      await pumpLibrary(tester, tv: true);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(find.byType(TextField), 'acao');
      await tester.pumpAndSettle();
      expect(shown(tester), ['Ação Dois']);
    });

    testWidgets('na TV, sair do campo volta a esperar o OK', (tester) async {
      await pumpLibrary(tester, tv: true);
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    });

    testWidgets('buscar no teclado leva o foco para o primeiro video',
        (tester) async {
      await pumpLibrary(tester, tv: true);
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'banana');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final focus = FocusManager.instance.primaryFocus?.context;
      expect(focus?.findAncestorWidgetOfExactType<EditableText>(), isNull);
      expect(
          find.descendant(
              of: find.byType(MediaCard), matching: find.text('Banana')),
          findsOneWidget);
      expect(
          focus?.findAncestorWidgetOfExactType<MediaCard>()?.item.title,
          'Banana');
    });

    testWidgets('na TV a seta para a direita leva ao seletor de ordem',
        (tester) async {
      await pumpLibrary(tester, tv: true);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      final focus = FocusManager.instance.primaryFocus?.context;
      expect(focus?.findAncestorWidgetOfExactType<EditableText>(), isNull);
      expect(focus?.findAncestorWidgetOfExactType<DropdownButton<LibrarySort>>(),
          isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);
    });

    testWidgets('fora da TV o campo ja abre editavel', (tester) async {
      await pumpLibrary(tester);

      expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    });

    testWidgets('na TV o foco sai do campo para baixo e volta para cima',
        (tester) async {
      await pumpLibrary(tester, tv: true);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(), isNotNull,
          reason: 'para cima volta ao campo de busca');
    });
  });
}
