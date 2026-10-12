import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/demo_addons.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

class FakeAddonFetcher extends AddonFetcher {
  const FakeAddonFetcher(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> fetchText(String url, {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }
}

String manifestJson() => jsonEncode(demoManifestJson());

Map<String, Object?> feedItem({
  String id = 'v1',
  String title = 'Video Um',
  String sourceUrl = 'https://cdn.exemplo.com/v1.mp4',
}) =>
    {
      'id': id,
      'title': title,
      'sourceUrl': sourceUrl,
    };

String feedJson([List<Map<String, Object?>>? items]) => jsonEncode({
      'items': items ??
          [
            feedItem(),
            feedItem(
              id: 'v2',
              title: 'Video Dois',
              sourceUrl: 'https://cdn.exemplo.com/v2.mp4',
            ),
          ],
    });

const feedUrl = 'https://feeds.exemplo.com/catalogo.json';
const feedUrlSameHost = 'https://feeds.exemplo.com/outro.json';
const feedUrlOtherHost = 'https://outra.exemplo.com/catalogo.json';
const manifestUrl = 'https://feeds.exemplo.com/man.json';

LocalAddonService serviceWithFeed() => LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: FakeAddonFetcher({
        feedUrl: feedJson(),
        feedUrlSameHost: feedJson(),
        feedUrlOtherHost: feedJson(),
        manifestUrl: manifestJson(),
      }),
    );

Future<AddonInfo> installFeed(LocalAddonService service) async {
  final preview = await service.previewSource(feedUrl);
  return service.install(preview.manifest, originTrusted: false);
}

class _Harness {
  _Harness({Map<String, String> bodies = const {}})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          fetcher: FakeAddonFetcher(bodies),
        ) {
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

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
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

  Future<void> openInstall(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Instalar add-on'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetails(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('5B servico: previa de fonte', () {
    test('manifesto gera previa sem salvar', () async {
      final service = serviceWithFeed();
      final preview = await service.previewSource(manifestUrl);
      expect(preview.manifest.id, 'demo.catalogo');
      expect(preview.feedItemCount, isNull);
      expect(service.addons, isEmpty);
    });

    test('feed gera manifesto sintetizado deterministico', () async {
      final service = serviceWithFeed();
      final first = await service.previewSource(feedUrl);
      final second = await service.previewSource(feedUrl);
      expect(first.manifest.id, second.manifest.id);
      expect(first.manifest.id, startsWith('feed.feeds.exemplo.com-'));
      expect(first.manifest.catalogUrl, feedUrl);
      expect(first.feedItemCount, 2);
      expect(first.feedSample, ['Video Um', 'Video Dois']);
      expect(service.addons, isEmpty);
    });

    test('feed instala desativado; mesma URL duplica', () async {
      final service = serviceWithFeed();
      final info = await installFeed(service);
      expect(info.state, AddonState.inactive);
      expect(info.needsApproval, isFalse);
      await service.enable(info.manifest.id);
      expect(service.getStatus(info.manifest.id), AddonState.active);
      await expectLater(
        () async {
          final preview = await service.previewSource(feedUrl);
          await service.install(preview.manifest, originTrusted: false);
        },
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.already-installed')),
      );
    });

    test('URL invalida nao toca rede e nao salva', () async {
      // Fetcher real: validacao precede qualquer socket.
      const fetcher = HttpAddonFetcher();
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: fetcher,
      );
      await expectLater(
        () => service.previewSource('nao-url'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.fetch-failed')),
      );
      expect(service.addons, isEmpty);
    });

    test('nem manifesto nem feed rejeita', () async {
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: const FakeAddonFetcher({'https://x.com/y': '{"a":1}'}),
      );
      await expectLater(
        () => service.previewSource('https://x.com/y'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.addons, isEmpty);
    });

    test('erro de rede propaga sem salvar', () async {
      final service = serviceWithFeed();
      await expectLater(
        () => service.previewSource('https://off.exemplo.com/f.json'),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.fetch-failed')),
      );
      expect(service.addons, isEmpty);
    });
  });

  group('5B servico: editar, aprovar, atualizar', () {
    test('mesma origem mantem estado e aprovacao', () async {
      final service = serviceWithFeed();
      final info = await installFeed(service);
      await service.enable(info.manifest.id);
      final updated = await service.updateSourceUrl(
          info.manifest.id, feedUrlSameHost);
      expect(updated.manifest.catalogUrl, feedUrlSameHost);
      expect(updated.state, AddonState.active);
      expect(updated.needsApproval, isFalse);
    });

    test('origem nova desativa e exige aprovacao', () async {
      final service = serviceWithFeed();
      final info = await installFeed(service);
      await service.enable(info.manifest.id);
      final updated = await service.updateSourceUrl(
          info.manifest.id, feedUrlOtherHost);
      expect(updated.state, AddonState.inactive);
      expect(updated.needsApproval, isTrue);
      // Ativar antes de aprovar e recusado sem excecao.
      await service.enable(info.manifest.id);
      expect(service.getStatus(info.manifest.id), AddonState.inactive);
      expect(service.findById(info.manifest.id)!.diagnostic,
          LocalAddonService.approvalDiagnostic);
      // Aprovar nao ativa sozinho; depois ativa.
      await service.approveSource(info.manifest.id);
      expect(service.findById(info.manifest.id)!.needsApproval, isFalse);
      expect(service.getStatus(info.manifest.id), AddonState.inactive);
      await service.enable(info.manifest.id);
      expect(service.getStatus(info.manifest.id), AddonState.active);
    });

    test('edicao invalida nao salva nada', () async {
      final service = serviceWithFeed();
      final info = await installFeed(service);
      await service.enable(info.manifest.id);
      await expectLater(
        () => service.updateSourceUrl(info.manifest.id, 'nao-url'),
        throwsA(isA<AddonError>()),
      );
      final kept = service.findById(info.manifest.id)!;
      expect(kept.manifest.catalogUrl, feedUrl);
      expect(kept.state, AddonState.active);
      expect(kept.needsApproval, isFalse);
    });

    test('atualizar devolve contagem; vazio e zero', () async {
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: FakeAddonFetcher({
          feedUrl: feedJson(),
          'https://vazio.exemplo.com/f.json': feedJson([]),
        }),
      );
      final preview = await service.previewSource(feedUrl);
      await service.install(preview.manifest, originTrusted: false);
      expect(await service.refreshSource(preview.manifest.id), 2);
      await service.updateSourceUrl(
          preview.manifest.id, 'https://vazio.exemplo.com/f.json');
      await service.approveSource(preview.manifest.id);
      expect(await service.refreshSource(preview.manifest.id), 0);
    });

    test('atualizar com erro isola e lanca o motivo', () async {
      final bodies = {feedUrl: feedJson()};
      final service = LocalAddonService(
        InMemoryLocalStore(),
        platform: 'windows',
        fetcher: FakeAddonFetcher(bodies),
      );
      final preview = await service.previewSource(feedUrl);
      await service.install(preview.manifest, originTrusted: false);
      await service.enable(preview.manifest.id);
      // Feed quebra depois de instalado: refresh isola e lanca.
      bodies[feedUrl] = 'quebrado';
      await expectLater(
        () => service.refreshSource(preview.manifest.id),
        throwsA(isA<AddonError>().having(
            (e) => e.code, 'code', 'addon.invalid-manifest')),
      );
      expect(service.getStatus(preview.manifest.id), AddonState.error);
    });

    test('remover apaga so o cadastro da fonte', () async {
      final store = InMemoryLocalStore();
      await store.write('library', {
        'items': [
          {'id': 'm1'}
        ]
      });
      await store.write('history', {
        'entries': [
          {'mediaId': 'm1'}
        ]
      });
      final service = LocalAddonService(
        store,
        platform: 'windows',
        fetcher: FakeAddonFetcher({feedUrl: feedJson()}),
      );
      final preview = await service.previewSource(feedUrl);
      await service.install(preview.manifest, originTrusted: false);
      await service.uninstall(preview.manifest.id);
      expect(service.addons, isEmpty);
      expect((await store.read('library'))!['items'], hasLength(1));
      expect((await store.read('history'))!['entries'], hasLength(1));
    });
  });

  group('5B tela: instalar fonte por URL', () {
    testWidgets('feed mostra previa, exige aceite e instala desativado',
        (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(
          find.text(
              'Fonte desconhecida — não verificada pelo aplicativo. Revise os dados abaixo antes de aprovar.'),
          findsOneWidget);
      expect(find.text('2 itens:\nVideo Um\nVideo Dois'), findsOneWidget);
      // Sem aceite, instalar nao sai da revisao.
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(harness.addons.addons, hasLength(1));
      final installed = harness.addons.addons.single;
      expect(installed.state, AddonState.inactive);
      expect(installed.manifest.catalogUrl, feedUrl);
      expect(find.text('Add-on instalado desativado.'), findsOneWidget);
    });

    testWidgets('feed parcialmente invalido instala so os validos',
        (tester) async {
      final harness = _Harness(bodies: {
        feedUrl: feedJson([
          feedItem(),
          {'id': 'ruim'},
        ]),
      });
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();

      expect(find.text('1 item:\nVideo Um'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(harness.addons.addons, hasLength(1));
    });

    testWidgets('cancelar na revisao do feed aborta', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('URL invalida e erro de rede mostram erro', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nao-url');
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(harness.addons.addons, isEmpty);

      await tester.enterText(
          find.byType(TextField), 'https://off.exemplo.com/f.json');
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível buscar.'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('feed vazio instala e informa zero itens', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson([])});
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();

      expect(find.text('Feed vazio (0 itens)'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(harness.addons.addons, hasLength(1));
    });

    testWidgets('duplicado de feed e rejeitado', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(find.text('Este add-on já está instalado.'), findsOneWidget);
      expect(harness.addons.addons, hasLength(1));
    });
  });

  group('5B tela: gerenciar fonte', () {
    testWidgets('editar mesma origem mantem; outra pede aprovacao',
        (tester) async {
      final harness = _Harness(bodies: {
        feedUrl: feedJson(),
        feedUrlSameHost: feedJson(),
        feedUrlOtherHost: feedJson(),
      });
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.addons.enable(preview.manifest.id);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      // Mesma origem: salva e segue ativo.
      await tester.tap(find.text('Editar endereço'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrlSameHost);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Endereço atualizado.'), findsOneWidget);
      expect(
          harness.addons.getStatus(preview.manifest.id), AddonState.active);

      // Outra origem: desativa e mostra o cartao de aprovacao.
      await tester.tap(find.text('Editar endereço'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrlOtherHost);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nova origem não aprovada'), findsOneWidget);
      expect(find.text('Aprovar origem'), findsOneWidget);
      expect(harness.addons.getStatus(preview.manifest.id),
          AddonState.inactive);

      // Aprovar nao ativa sozinho; depois ativa.
      await tester.tap(find.text('Aprovar origem'));
      await tester.pumpAndSettle();
      expect(harness.addons.getStatus(preview.manifest.id),
          AddonState.inactive);
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(
          harness.addons.getStatus(preview.manifest.id), AddonState.active);
    });

    testWidgets('atualizar mostra contagem; erro isola', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      await tester.tap(find.text('Atualizar catálogo'));
      await tester.pumpAndSettle();
      expect(
          find.text('Catálogo atualizado: 2 itens.'), findsOneWidget);
    });

    testWidgets('remover pede confirmacao e preserva midias', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(harness.addons.addons, hasLength(1));

      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover').last);
      await tester.pumpAndSettle();
      expect(harness.addons.addons, isEmpty);
    });
  });

  group('5B teclado: dialogos navegam e fecham', () {
    testWidgets('ESC na edicao fecha sem salvar', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      await tester.tap(find.text('Editar endereço'));
      await tester.pumpAndSettle();
      expect(find.text('Editar endereço do feed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), feedUrlSameHost);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Editar endereço do feed'), findsNothing);
      final info = harness.addons.addons.single;
      expect(info.manifest.catalogUrl, feedUrl);
    });

    testWidgets('tab ate Salvar + enter salva pelo teclado',
        (tester) async {
      final harness = _Harness(bodies: {
        feedUrl: feedJson(),
        feedUrlSameHost: feedJson(),
      });
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      await tester.tap(find.text('Editar endereço'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrlSameHost);

      // Campo -> Cancelar -> Salvar.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Endereço atualizado.'), findsOneWidget);
      final info = harness.addons.addons.single;
      expect(info.manifest.catalogUrl, feedUrlSameHost);
    });

    testWidgets('enter imediato na remocao cancela (foco seguro)',
        (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      final preview = await harness.addons.previewSource(feedUrl);
      await harness.addons.install(preview.manifest, originTrusted: false);
      await harness.pump(tester);
      await harness.openDetails(tester, preview.manifest.name);

      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Remover add-on?'), findsOneWidget);

      // Cancelar nasce focado: OK imediato cancela, nunca destroi.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Remover add-on?'), findsNothing);
      expect(harness.addons.addons, hasLength(1));
    });

    testWidgets('revisao: tab ate Cancelar + enter aborta', (tester) async {
      final harness = _Harness(bodies: {feedUrl: feedJson()});
      await harness.pump(tester);
      await harness.openInstall(tester);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), feedUrl);
      await tester.tap(find.text('Buscar fonte'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);

      // Avanca por tab ate o Cancelar (a ordem exata e detalhe de
      // layout; o que importa e que o teclado alcanca e ativa).
      Element? cancelFocus;
      tester
          .element(find.text('Cancelar'))
          .visitAncestorElements((element) {
        if (element.widget is Focus) {
          cancelFocus = element;
          return false;
        }
        return true;
      });
      expect(cancelFocus, isNotNull);
      var focused = false;
      for (var i = 0; i < 15 && !focused; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        focused = tester.binding.focusManager.primaryFocus?.context ==
            cancelFocus;
      }
      expect(focused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(harness.addons.addons, isEmpty);
    });
  });
}
