import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/home/home_addon_rows.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/addon_fetcher.dart';
import 'support/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/media_card.dart';

/// T8/T9: fileira por add-on ativo no Início do desktop e da TV. Corpo por URL;
/// sem corpo, falha; [gate] segura a resposta para flagrar a tela
/// desenhada antes da rede.
class _Fetcher extends AddonFetcher {
  final bodies = <String, String>{};
  final calls = <String>[];
  Completer<void>? gate;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    calls.add(url);
    await gate?.future;
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

String _url(String id) => 'https://fonte.exemplo.org/$id.json';

String _feed(String prefix, int count) => jsonEncode({
      'items': [
        for (var i = 0; i < count; i++)
          {
            'id': '$prefix$i',
            'title': '$prefix título $i',
            'subtitle': 'Série $prefix',
            'sourceUrl': 'https://cdn.exemplo.org/$prefix$i.mp4',
          },
      ],
    });

Future<void> _install(
  LocalAddonService addons,
  String id,
  String name, {
  bool active = true,
}) async {
  final json = demoManifestJson()
    ..['id'] = id
    ..['name'] = name
    ..['catalogUrl'] = _url(id);
  await addons.install(await addons.validate(json), originTrusted: true);
  if (active) await addons.enable(id);
}

LocalAddonService _service(_Fetcher fetcher) => LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: fetcher,
    );

class _Harness {
  _Harness()
      : fetcher = _Fetcher(),
        preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        guard = StartupGuard(InMemoryLocalStore());

  final _Fetcher fetcher;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final StartupGuard guard;
  late final LocalAddonService addons = _service(fetcher);
  final NoOpMediaPlayerService player = const NoOpMediaPlayerService();

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1920, 1080),
    List<MainDestination> hidden = const [],
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await preferences.update(preferences.current.copyWith(
      showOnboarding: false,
      hiddenDestinations: hidden,
    ));
    await tester.pumpWidget(PlayerApp(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: NoOpWindowService(),
      addonService: addons,
      startupGuard: guard,
      mobilePlatform: false,
      diagnosticsService: DiagnosticsService(
        store: InMemoryLocalStore(),
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }
}

void main() {
  group('quais add-ons têm fileira', () {
    test('ativo e com erro entram; inativo fica de fora', () async {
      final addons = _service(_Fetcher());
      await _install(addons, 'a.ativo', 'Ativo');
      await _install(addons, 'b.inativo', 'Inativo', active: false);
      await _install(addons, 'c.erro', 'Com erro');
      await addons.getCatalog('c.erro');
      expect(addons.getStatus('c.erro'), AddonState.error);

      final ids = homeAddonRowInfos(addons.addons)
          .map((info) => info.manifest.id)
          .toList();

      expect(ids, ['a.ativo', 'c.erro']);
    });

    test('destino escondido e modo seguro não têm fileira', () async {
      final addons = _service(_Fetcher());
      await _install(addons, 'a.ativo', 'Ativo');

      expect(
        homeAddonRowInfos(
          addons.addons,
          hidden: const [MainDestination.addons],
        ),
        isEmpty,
      );
      expect(homeAddonRowInfos(addons.addons, safeMode: true), isEmpty);
    });
  });

  group('carga das fileiras', () {
    late _Fetcher fetcher;
    late LocalAddonService addons;
    late HomeAddonRows rows;

    setUp(() {
      fetcher = _Fetcher();
      addons = _service(fetcher);
      rows = HomeAddonRows(addons);
    });

    tearDown(() => rows.dispose());

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('mostra no máximo 20 itens', () async {
      fetcher
        ..gate = Completer<void>()
        ..bodies[_url('a')] = _feed('a', 30);
      await _install(addons, 'a', 'A');
      await settle();
      expect(rows.stateOf('a').loading, isTrue);

      fetcher.gate!.complete();
      await settle();

      expect(rows.stateOf('a').loading, isFalse);
      expect(rows.stateOf('a').items, hasLength(20));
    });

    test('fileira vazia que sumiu volta quando o feed ganha itens', () async {
      fetcher.bodies[_url('a')] = jsonEncode({'items': <Object?>[]});
      await _install(addons, 'a', 'A');
      rows.reconcile();
      await settle();
      expect(rows.visibleInfos, isEmpty);

      // Sem novidade, voltar ao app não faz a fileira reaparecer.
      rows.refreshEmpty();
      await settle();
      expect(rows.visibleInfos, isEmpty);

      fetcher
        ..gate = Completer<void>()
        ..bodies[_url('a')] = _feed('a', 3);
      rows.refreshEmpty();
      await settle();
      // Durante a busca a fileira segue escondida: sem piscar "carregando".
      expect(rows.visibleInfos, isEmpty);
      expect(rows.stateOf('a').loading, isFalse);

      fetcher.gate!.complete();
      await settle();

      expect(rows.visibleInfos.map((i) => i.manifest.id), ['a']);
      expect(rows.stateOf('a').items, hasLength(3));
    });

    test('guarda em memória; só Atualizar busca de novo', () async {
      fetcher.bodies[_url('a')] = _feed('a', 2);
      await _install(addons, 'a', 'A');
      rows.reconcile();
      await settle();
      rows.reconcile();
      await settle();
      expect(fetcher.calls, hasLength(1));

      fetcher.bodies[_url('a')] = _feed('a', 3);
      await rows.refresh('a');

      expect(fetcher.calls, hasLength(2));
      expect(rows.stateOf('a').items, hasLength(3));
    });

    test('falha afeta só a fileira do add-on', () async {
      fetcher.bodies[_url('b')] = _feed('b', 2);
      await _install(addons, 'a', 'A');
      await _install(addons, 'b', 'B');

      rows.reconcile();
      await settle();

      expect(rows.stateOf('a').error, isNotNull);
      expect(rows.stateOf('a').items, isEmpty);
      // Falha nesta sessão não ganha tentativa automática.
      expect(fetcher.calls.where((url) => url == _url('a')), hasLength(1));
      expect(rows.stateOf('b').error, isNull);
      expect(rows.stateOf('b').items, hasLength(2));
    });

    test('versão nova durante a busca busca de novo', () async {
      fetcher
        ..gate = Completer<void>()
        ..bodies[_url('a')] = _feed('a', 1)
        ..bodies[_url('novo')] = _feed('novo', 2);
      await _install(addons, 'a', 'A');
      await settle();

      final update = addons.updateSourceUrl('a', _url('novo'));
      fetcher.gate!.complete();
      await update;
      await settle();
      await settle();

      expect(rows.stateOf('a').items, hasLength(2));
    });

    test('Tentar de novo recupera a fileira', () async {
      await _install(addons, 'a', 'A');
      rows.reconcile();
      await settle();
      expect(rows.stateOf('a').error, isNotNull);

      fetcher.bodies[_url('a')] = _feed('a', 2);
      await rows.retry('a');

      expect(addons.getStatus('a'), AddonState.active);
      expect(rows.stateOf('a').error, isNull);
      expect(rows.stateOf('a').items, hasLength(2));
      expect(fetcher.calls, hasLength(2));
    });

    /// Add-on salvo em erro por uma sessão anterior.
    Future<InMemoryLocalStore> reopenWithError() async {
      final json = demoManifestJson()
        ..['id'] = 'a'
        ..['catalogUrl'] = _url('a');
      final store = InMemoryLocalStore();
      await store.write(LocalAddonService.storeKey, {
        'items': [
          AddonInfo(
            manifest: AddonManifest.fromMap(json),
            state: AddonState.error,
            diagnostic: 'Falha antiga.',
            installedAt: DateTime(2026),
            approvedOrigin: 'fonte.exemplo.org',
          ).toMap(),
        ],
      });
      rows.dispose();
      addons = LocalAddonService(store, platform: 'windows', fetcher: fetcher);
      await addons.load();
      rows = HomeAddonRows(addons);
      return store;
    }

    test('ao abrir, erro de antes tenta sozinho e se recupera', () async {
      fetcher.bodies[_url('a')] = _feed('a', 2);
      final store = await reopenWithError();

      rows.reconcile();
      await settle();

      expect(addons.getStatus('a'), AddonState.active);
      expect(rows.stateOf('a').items, hasLength(2));
      expect(fetcher.calls, hasLength(1));
      // Não é alteração do usuário: o modo seguro segue sem o que desfazer.
      final doc = await store.read(LocalAddonService.storeKey);
      expect(doc!['lastChange'], isNull);
    });

    test('ao abrir, tenta uma vez só e mostra o erro', () async {
      await reopenWithError();

      rows.reconcile();
      await settle();
      await settle();
      rows.reconcile();
      await settle();

      expect(fetcher.calls, hasLength(1));
      expect(addons.getStatus('a'), AddonState.error);
      expect(rows.stateOf('a').error, isNotNull);
    });

    test('Tentar de novo mantém a fileira visível durante a busca', () async {
      await _install(addons, 'a', 'A');
      await settle();
      expect(rows.stateOf('a').error, isNotNull);

      fetcher
        ..gate = Completer<void>()
        ..bodies[_url('a')] = _feed('a', 1);
      final retry = rows.retry('a');
      await settle();

      expect(rows.stateOf('a').loading, isTrue);
      expect(rows.visibleInfos, hasLength(1));

      fetcher.gate!.complete();
      await retry;
      expect(rows.stateOf('a').items, hasLength(1));
    });

    test('Tentar de novo não vira a última alteração do modo seguro',
        () async {
      final store = InMemoryLocalStore();
      rows.dispose();
      addons = LocalAddonService(store, platform: 'windows', fetcher: fetcher);
      rows = HomeAddonRows(addons);
      await _install(addons, 'a', 'A');
      fetcher.bodies[_url('b')] = _feed('b', 1);
      await _install(addons, 'b', 'B');
      await settle();
      expect(addons.getStatus('a'), AddonState.error);

      await rows.retry('a');

      final doc = await store.read(LocalAddonService.storeKey);
      expect((doc!['lastChange'] as Map)['id'], 'b');
    });

    test('Atualizar em fileira com erro busca de novo', () async {
      await _install(addons, 'a', 'A');
      await settle();
      final before = fetcher.calls.length;

      fetcher.bodies[_url('a')] = _feed('a', 2);
      await rows.refresh('a');

      expect(fetcher.calls.length, before + 1);
      expect(rows.stateOf('a').error, isNull);
      expect(rows.stateOf('a').items, hasLength(2));
    });

    test('add-on que não pode sair do erro mostra o motivo', () async {
      // Documento salvo: em erro, e o aparelho não está nas plataformas.
      final json = demoManifestJson()
        ..['id'] = 'a'
        ..['catalogUrl'] = _url('a')
        ..['supportedPlatforms'] = ['android'];
      final store = InMemoryLocalStore();
      await store.write(LocalAddonService.storeKey, {
        'items': [
          AddonInfo(
            manifest: AddonManifest.fromMap(json),
            state: AddonState.error,
            installedAt: DateTime(2026),
            approvedOrigin: 'fonte.exemplo.org',
          ).toMap(),
        ],
      });
      rows.dispose();
      addons = LocalAddonService(store, platform: 'windows', fetcher: fetcher);
      await addons.load();
      rows = HomeAddonRows(addons);

      await rows.retry('a');
      await settle();

      expect(addons.getStatus('a'), AddonState.error);
      expect(rows.stateOf('a').error, contains('compatível'));
    });

    test('desativar e ativar muda a fileira sem reiniciar', () async {
      fetcher.bodies[_url('a')] = _feed('a', 2);
      await _install(addons, 'a', 'A');
      rows.reconcile();
      await settle();

      await addons.disable('a');
      await settle();
      expect(rows.infos, isEmpty);

      await addons.enable('a');
      await settle();
      expect(rows.infos.single.manifest.id, 'a');
      expect(rows.stateOf('a').items, hasLength(2));
      expect(fetcher.calls, hasLength(2));
    });
  });

  group('fileiras no Início', () {
    testWidgets('a tela desenha antes da rede e o catálogo chega depois',
        (tester) async {
      final harness = _Harness();
      harness.fetcher
        ..gate = Completer<void>()
        ..bodies[_url('a')] = _feed('a', 3);
      await _install(harness.addons, 'a', 'Catálogo A');
      await harness.library.upsert(MediaItem(
        id: 'local',
        title: 'Vídeo local',
        sourceType: MediaSourceType.local,
        source: '/v/local.mp4',
        addedAt: DateTime(2026),
      ));

      await harness.pump(tester, settle: false);
      await tester.pump();

      expect(find.text('Vídeo local'), findsOneWidget);
      expect(find.text('Catálogo A'), findsOneWidget);
      expect(find.text('a título 0'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      harness.fetcher.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('a título 0'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('o cartão do catálogo é pôster 2:3', (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 3);
      await _install(harness.addons, 'a', 'Catálogo A');

      await harness.pump(tester);

      final card = tester.widget<MediaPosterCard>(
        find.byType(MediaPosterCard).first,
      );
      expect(card.aspectRatio, MediaPosterCard.posterAspect);
      expect(card.width, 240);
      expect(find.text('Série a'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falha mostra Tentar de novo só na fileira dela',
        (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('b')] = _feed('b', 1);
      await _install(harness.addons, 'a', 'Catálogo A');
      await _install(harness.addons, 'b', 'Catálogo B');

      await harness.pump(tester);

      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text('b título 0'), findsOneWidget);

      harness.fetcher.bodies[_url('a')] = _feed('a', 1);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.text('Tentar de novo'), findsNothing);
      expect(find.text('a título 0'), findsOneWidget);
    });

    testWidgets('Ver tudo abre o catálogo completo', (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(harness.addons, 'a', 'Catálogo A');

      await harness.pump(tester);
      await tester.tap(find.text('Ver tudo'));
      await tester.pumpAndSettle();

      expect(find.text('Buscar no catálogo'), findsOneWidget);
    });

    testWidgets('pôster abre o player pelo fluxo do catálogo', (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(harness.addons, 'a', 'Catálogo A');

      await harness.pump(tester);
      await tester.tap(find.byType(MediaPosterCard).first);
      await tester.pumpAndSettle();

      expect(harness.library.findById('a:a0'), isNotNull);
      expect(find.byTooltip('Fechar'), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo A'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('abrir de novo pelo pôster mantém a posição salva',
        (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(harness.addons, 'a', 'Catálogo A');
      final seen = DateTime(2026, 10, 30);
      await harness.library.upsert(MediaItem(
        id: 'a:a0',
        title: 'a título 0',
        sourceType: MediaSourceType.url,
        source: 'https://cdn.exemplo.org/a0.mp4',
        duration: const Duration(minutes: 90),
        addedAt: DateTime(2026),
        lastPosition: const Duration(minutes: 5),
        lastPlayedAt: seen,
      ));

      await harness.pump(tester);
      final poster = find.byWidgetPredicate((widget) =>
          widget is MediaPosterCard &&
          widget.aspectRatio == MediaPosterCard.posterAspect);
      await tester.ensureVisible(poster);
      await tester.pumpAndSettle();
      await tester.tap(poster);
      await tester.pumpAndSettle();

      final saved = harness.library.findById('a:a0')!;
      expect(saved.lastPosition, const Duration(minutes: 5));
      expect(saved.duration, const Duration(minutes: 90));
      expect(saved.lastPlayedAt, seen);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('setas andam pelos pôsteres e Enter abre o item',
        (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 3);
      await _install(harness.addons, 'a', 'Catálogo A');

      await harness.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harness.library.findById('a:a1'), isNotNull);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus!.context!;
      final card = focused.findAncestorWidgetOfExactType<MediaPosterCard>();
      expect(card?.item.id, 'a:a1');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('vazio oferece Instalar add-on', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);

      await tester.tap(find.text('Instalar add-on'));
      await tester.pumpAndSettle();
      expect(find.text('Instalar de zip'), findsOneWidget);
    });

    testWidgets('catálogo vazio some e volta ao estado vazio', (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 0);
      await _install(harness.addons, 'a', 'Catálogo A');

      await harness.pump(tester);

      expect(find.text('Catálogo A'), findsNothing);
      expect(find.text('Nenhum vídeo por aqui ainda'), findsOneWidget);
    });

    testWidgets('destino escondido e modo seguro não buscam nada',
        (tester) async {
      final hidden = _Harness();
      hidden.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(hidden.addons, 'a', 'Catálogo A');
      await hidden.pump(tester, hidden: const [MainDestination.addons]);
      expect(find.text('Catálogo A'), findsNothing);
      expect(hidden.fetcher.calls, isEmpty);

      final safe = _Harness();
      safe.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(safe.addons, 'a', 'Catálogo A');
      await safe.guard.setManualSafeMode(true);
      await safe.pump(tester);
      expect(find.text('Catálogo A'), findsNothing);
      expect(safe.fetcher.calls, isEmpty);
    });

    testWidgets('TV mostra a fileira do add-on como no desktop (T9)',
        (tester) async {
      final harness = _Harness();
      harness.fetcher.bodies[_url('a')] = _feed('a', 1);
      await _install(harness.addons, 'a', 'Catálogo A');
      await harness.preferences
          .update(harness.preferences.current.copyWith(tvMode: true));

      await harness.pump(tester, size: const Size(960, 540));

      expect(find.text('Catálogo A'), findsOneWidget);
      expect(find.text('a título 0'), findsOneWidget);
      expect(harness.fetcher.calls, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
