import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/tv_info_service.dart';
import 'package:player/services/window_service.dart';

class _FailingStore implements LocalStore {
  @override
  Future<Map<String, Object?>?> read(String key) async =>
      throw StateError('disco falhou');

  @override
  Future<void> write(String key, Map<String, Object?> value) async =>
      throw StateError('disco falhou');

  @override
  Future<void> remove(String key) async => throw StateError('disco falhou');

  @override
  Future<void> clear() async => throw StateError('disco falhou');
}

class _Harness {
  _Harness({LocalStore? store, Set<String> faultyIds = const {}})
      : store = store ?? InMemoryLocalStore(),
        preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService() {
    addons = LocalAddonService(
      this.store,
      platform: 'windows',
      faultyIds: faultyIds,
    );
    guard = StartupGuard(this.store);
    diagnostics = DiagnosticsService(
      store: this.store,
      preferences: preferences,
      library: library,
      history: history,
      player: player,
      addons: addons,
      guard: guard,
    );
  }

  final LocalStore store;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  late final LocalAddonService addons;
  late final StartupGuard guard;
  late final DiagnosticsService diagnostics;

  Future<void> seed() async {
    await library.upsert(MediaItem(
      id: 'v1',
      title: 'Um',
      sourceType: MediaSourceType.url,
      source: 'https://videos.exemplo.com/privado/um.mp4',
      addedAt: DateTime(2026, 1, 1),
    ));
    await library.upsert(MediaItem(
      id: 'v2',
      title: 'Dois',
      sourceType: MediaSourceType.local,
      source: r'C:\Secreto\dois.mp4',
      addedAt: DateTime(2026, 1, 1),
    ));
    await library.toggleFavorite('v1');
    await history.record(HistoryEntry(
      mediaId: 'v1',
      accessedAt: DateTime(2026, 1, 2),
    ));
    await addons.install(
      AddonManifest.fromMap(demoManifestJson()),
      originTrusted: false,
    );
    await addons.addRepository(
      name: 'Repo',
      originUrl: 'https://repos.exemplo.com/secreto.json',
    );
    await guard.recordError(
        'falha em https://videos.exemplo.com/privado/um.mp4');
  }
}

void main() {
  group('DiagnosticsService coleta', () {
    test('collect junta contagens e estados', () async {
      final harness = _Harness(faultyIds: const {'bad.addon'});
      await harness.seed();
      await harness.addons.install(
        AddonManifest.fromMap(demoManifestJson(id: 'bad.addon')),
        originTrusted: false,
      );
      await harness.addons.enable('bad.addon');
      await harness.addons.getCatalog('bad.addon');

      final report = await harness.diagnostics.collect();
      expect(report.appVersion, isNotEmpty);
      expect(report.platform, isNotEmpty);
      expect(report.playerLabel, 'ocioso');
      expect(report.storageOk, isTrue);
      expect(report.libraryCount, 2);
      expect(report.favoritesCount, 1);
      expect(report.historyCount, 1);
      expect(report.addonsTotal, 2);
      expect(report.addonsError, 1);
      expect(report.reposCount, 1);
      expect(report.safeMode, isFalse);
      expect(report.safeModeLabel, 'não');
      expect(report.lastErrorAt, isNotNull);
      expect(report.lastChangeName, 'Catálogo Demo');
    });

    test('falha de armazenamento vira estado, nao excecao', () async {
      final harness = _Harness(store: _FailingStore());
      final report = await harness.diagnostics.collect();
      expect(report.storageOk, isFalse);
    });
  });

  group('DiagnosticsService acoes', () {
    test('restoreDefaults so mexe nas prefs', () async {
      final harness = _Harness();
      await harness.seed();
      await harness.preferences.update(
        harness.preferences.current.copyWith(initialVolume: 0.1),
      );

      await harness.diagnostics.restoreDefaults();

      expect(harness.preferences.current.initialVolume, 1.0);
      expect(harness.library.items, hasLength(2));
      expect(harness.history.entries, hasLength(1));
      expect(harness.addons.addons, hasLength(1));
    });

    test('clearAppData apaga tudo menos midias', () async {
      final harness = _Harness();
      await harness.seed();

      await harness.diagnostics.clearAppData();

      expect(harness.library.items, isEmpty);
      expect(harness.history.entries, isEmpty);
      expect(harness.addons.addons, isEmpty);
      expect(harness.addons.repositories, isEmpty);
      expect(harness.guard.lastError, isNull);
      // Volta a apresentacao inicial no proximo arranque.
      expect(harness.preferences.current.showOnboarding, isTrue);
      // Documento persistido esvaziado (midias em disco intactas: os
      // servicos nunca apagam arquivos).
      expect((await harness.store.read('addons'))?['items'], isEmpty);
    });

    test('clearEphemeral limpa o ultimo erro', () async {
      final harness = _Harness();
      await harness.guard.recordError('boom');
      await harness.diagnostics.clearEphemeral();
      expect(harness.guard.lastError, isNull);
    });
  });

  group('DiagnosticsService relatorio', () {
    test('exportacao tem estados e nenhum dado sensivel', () async {
      final harness = _Harness();
      await harness.seed();
      final report = await harness.diagnostics.collect();
      final text = harness.diagnostics.buildReport(report);

      expect(text, contains('Relatório de diagnóstico'));
      expect(text, contains('Biblioteca: 2 vídeos, 1 favoritos'));
      expect(text, contains('Add-ons: 1 instalados'));
      expect(text, contains('Último erro: '));
      // Nada que identifique midias, origens ou credenciais.
      expect(text.contains('videos.exemplo.com'), isFalse);
      expect(text.contains('repos.exemplo.com'), isFalse);
      expect(text.contains(r'C:\Secreto'), isFalse);
      expect(text.contains('falha em http'), isFalse);
    });

    test('exportacao nunca contem URL, caminho ou credencial', () async {
      final harness = _Harness();
      await harness.seed();
      await harness.guard.recordError(StateError(
          'token=segredo em C:\\tmp\\x.mp4 via https://a.test/v?a=1'));
      final report = await harness.diagnostics.collect();
      final text = harness.diagnostics.buildReport(report);

      expect(text.contains(RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://')), isFalse);
      expect(text.contains(RegExp(r'[A-Za-z]:\\')), isFalse);
      expect(text.contains('segredo'), isFalse);
      expect(text.contains('[credencial]'), isFalse);
    });

    test('exportacao identifica o tipo do erro', () async {
      final harness = _Harness();
      await harness.guard.recordError('cannot decode: codec missing');
      final report = await harness.diagnostics.collect();
      expect(report.lastErrorKind, PlaybackErrorKind.decoder);
      final text = harness.diagnostics.buildReport(report);
      expect(text, contains('Tipo do último erro: decodificador'));
      expect(text.contains('codec missing'), isFalse);
    });

    test('instrucoes nomeiam a plataforma atual', () async {
      final harness = _Harness();
      final text = harness.diagnostics.reinstallInstructions();
      expect(text, contains('Seus vídeos não são afetados'));
    });
  });

  test('leanback sem canal nativo responde false', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await const TvInfoService().isTv, isFalse);
  });

  group('tela Diagnóstico e recuperação', () {
    testWidgets('abre pelas configurações e mostra o estado',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Diagnóstico e recuperação'));
      await tester.tap(find.text('Diagnóstico e recuperação'));
      await tester.pumpAndSettle();

      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('0.1.0-rc.1'), findsOneWidget);
      expect(find.text('ocioso'), findsOneWidget);
      expect(find.text('2 vídeos, 1 favoritos'), findsOneWidget);
      expect(find.text('1 entradas'), findsOneWidget);
      expect(find.text('1 instalados (0 ativos, 1 inativos, 0 em erro)'),
          findsOneWidget);
      expect(find.text('1 cadastrados'), findsOneWidget);
    });

    testWidgets('secao Exibicao mostra as metricas reais',
        (tester) async {
      TvPanelMetrics.reset();
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      await tester.ensureVisible(find.text('Exibição'));
      // Janela 800x600 com densidade 3.0 (harness, via window service).
      expect(find.text('800 × 600'), findsOneWidget);
      expect(find.text('3.0'), findsOneWidget);
      expect(find.text('2400 × 1800'), findsOneWidget);
      expect(find.text('paisagem'), findsOneWidget);
      expect(find.text('windows'), findsNWidgets(2));
      expect(find.text('normal'), findsOneWidget);
      expect(find.text('Leanback'), findsOneWidget);
      expect(find.text('Painel TV'), findsOneWidget);
      expect(find.text('não exibido ainda'), findsOneWidget);
    });

    testWidgets('restaurar padrões preserva dados', (tester) async {
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.preferences.update(
        harness.preferences.current.copyWith(initialVolume: 0.1),
      );
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      await tester.ensureVisible(find.text('Restaurar padrões'));
      await tester.tap(find.text('Restaurar padrões'));
      await tester.pumpAndSettle();

      expect(harness.preferences.current.initialVolume, 1.0);
      expect(harness.library.items, hasLength(2));
      expect(harness.history.entries, hasLength(1));
      expect(harness.addons.addons, hasLength(1));
      expect(find.textContaining('Padrões restaurados.'), findsOneWidget);
    });

    testWidgets('limpar dados pede confirmação e apaga tudo',
        (tester) async {
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      await tester.ensureVisible(find.text('Limpar dados do app'));
      await tester.tap(find.text('Limpar dados do app'));
      await tester.pumpAndSettle();
      expect(find.text('Apagar todos os dados do app?'), findsOneWidget);
      expect(
          find.textContaining('add-ons, repositórios'), findsOneWidget);
      expect(find.textContaining('NÃO serão tocados'), findsOneWidget);

      await tester.tap(find.text('Apagar tudo'));
      await tester.pumpAndSettle();

      expect(harness.library.items, isEmpty);
      expect(harness.history.entries, isEmpty);
      expect(harness.addons.addons, isEmpty);
      expect(find.textContaining('Dados do app apagados.'),
          findsOneWidget);
    });

    testWidgets('cancelar a limpeza mantem os dados', (tester) async {
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      await tester.ensureVisible(find.text('Limpar dados do app'));
      await tester.tap(find.text('Limpar dados do app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(harness.library.items, hasLength(2));
      expect(harness.addons.addons, hasLength(1));
    });

    testWidgets('exportar copia sem dados sensiveis', (tester) async {
      final harness = _WidgetHarness();
      await harness.seed();
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      // A tela mostra a mensagem higienizada (sem URL); a area de transferencia
      // recebe o relatorio higienizado (capturado pelo mock).
      expect(find.textContaining('falha em [url]'), findsOneWidget);
      expect(find.textContaining('videos.exemplo.com'), findsNothing);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.ensureVisible(find.text('Exportar relatório'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportar relatório'));
      await tester.pumpAndSettle();

      expect(copied, isNotNull);
      expect(find.textContaining('Relatório copiado ('), findsOneWidget);
      expect(copied, contains('Relatório de diagnóstico'));
      expect(copied!.contains('videos.exemplo.com'), isFalse);
      expect(copied!.contains('repos.exemplo.com'), isFalse);
      expect(copied!.contains('Secreto'), isFalse);
      expect(copied!.contains('falha em http'), isFalse);
    });

    testWidgets('tela mostra o tipo do erro', (tester) async {
      final harness = _WidgetHarness();
      await harness.guard.recordError('timed out after 30s');
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      expect(find.text('Tipo do erro'), findsOneWidget);
      expect(find.text('tempo esgotado'), findsOneWidget);
    });

    testWidgets('modo manual alterna pelo interruptor', (tester) async {
      final harness = _WidgetHarness();
      await harness.pump(tester);
      await harness.openDiagnostics(tester);

      expect(harness.guard.manualSafeMode, isFalse);
      await tester.ensureVisible(find.text('Ativar modo seguro'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(harness.guard.manualSafeMode, isTrue);
      expect(
          find.textContaining('não desinstala nada'), findsOneWidget);
    });

    testWidgets('faixa de modo seguro abre o diagnóstico', (tester) async {
      final harness = _WidgetHarness();
      await harness.guard.beginBoot();
      await harness.guard.setManualSafeMode(true);
      await harness.pump(tester);

      await tester.tap(find.text('Diagnóstico'));
      await tester.pumpAndSettle();
      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('sim (manual)'), findsOneWidget);
    });
  });
}

class _WidgetHarness {
  _WidgetHarness()
      : store = InMemoryLocalStore(),
        preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService() {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
    addons = LocalAddonService(store, platform: 'windows');
    guard = StartupGuard(store);
    diagnostics = DiagnosticsService(
      store: store,
      preferences: preferences,
      library: library,
      history: history,
      player: player,
      addons: addons,
      guard: guard,
    );
  }

  final InMemoryLocalStore store;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  late final LocalAddonService addons;
  late final StartupGuard guard;
  late final DiagnosticsService diagnostics;

  Future<void> seed() async {
    await library.upsert(MediaItem(
      id: 'v1',
      title: 'Um',
      sourceType: MediaSourceType.url,
      source: 'https://videos.exemplo.com/privado/um.mp4',
      addedAt: DateTime(2026, 1, 1),
    ));
    await library.upsert(MediaItem(
      id: 'v2',
      title: 'Dois',
      sourceType: MediaSourceType.local,
      source: r'C:\Secreto\dois.mp4',
      addedAt: DateTime(2026, 1, 1),
    ));
    await library.toggleFavorite('v1');
    await history.record(HistoryEntry(
      mediaId: 'v1',
      accessedAt: DateTime(2026, 1, 2),
    ));
    await addons.install(
      AddonManifest.fromMap(demoManifestJson()),
      originTrusted: false,
    );
    await addons.addRepository(
      name: 'Repo',
      originUrl: 'https://repos.exemplo.com/secreto.json',
    );
    await guard.recordError(
        'falha em https://videos.exemplo.com/privado/um.mp4');
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PlayerApp(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: windows,
      addonService: addons,
      startupGuard: guard,
      diagnosticsService: diagnostics,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openDiagnostics(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Diagnóstico e recuperação'));
    await tester.tap(find.text('Diagnóstico e recuperação'));
    await tester.pumpAndSettle();
  }
}
