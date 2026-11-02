import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/file_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_kit_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/supervised_player_service.dart';
import 'package:player/services/window_service.dart';
import 'package:player/widgets/media_card.dart';

/// Checklist da 0.4.0 no Windows real: disco, rede e motor de vídeo de
/// verdade, em pastas temporárias (os dados do usuário não são tocados).
/// O link usa servidor em loopback, liberado só aqui por `allowPrivate`.
/// Rodar da raiz do projeto:
/// `flutter test -d windows integration_test/addons_desktop_test.dart`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final zips = '${Directory.current.path}/test_assets/addons';

  late Directory temp;
  late Directory packages;
  late HttpServer server;
  late InMemoryPreferencesService preferences;
  late InMemoryLibraryService library;
  late InMemoryHistoryService history;
  late LocalAddonService addons;

  Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder,
      {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    final texts = [
      for (final element in find.byType(Text).evaluate())
        (element.widget as Text).data ?? '',
    ].where((text) => text.isNotEmpty).join(' | ');
    fail('Não apareceu em ${seconds}s: $finder. Na tela: $texts');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder.first);
    await pumpFor(tester, 200);
    await tester.tap(finder.first);
    await pumpFor(tester);
  }

  /// Escreve o caminho de um zip e lê o pacote.
  Future<void> readZip(WidgetTester tester, String path) async {
    final field = find.widgetWithText(TextField, 'Caminho do pacote');
    await tester.ensureVisible(field);
    // Direto no campo: no modo real, o enterText só vale na primeira vez.
    tester.widget<TextField>(field).controller!.text = path;
    await pumpFor(tester, 100);
    await tapText(tester, 'Ler pacote');
    await pumpFor(tester, 900);
  }

  setUpAll(() async {
    MediaKit.ensureInitialized();
    temp = await Directory.systemTemp.createTemp('olympus_it');
    packages = Directory('${temp.path}/addons')..createSync();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final file = File('$zips${request.uri.path}');
      if (await file.exists()) {
        request.response.headers.contentType = ContentType.binary;
        await request.response.addStream(file.openRead());
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  testWidgets('checklist 0.4.0 no Windows', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);

    preferences = InMemoryPreferencesService();
    await preferences
        .update(preferences.current.copyWith(showOnboarding: false));
    library = InMemoryLibraryService();
    history = InMemoryHistoryService();
    final store = FileLocalStore(Directory('${temp.path}/store'));
    final guard = StartupGuard(store);
    addons = LocalAddonService(
      store,
      fetcher: const HttpAddonFetcher(allowPrivate: true),
      allowUnknownSources: () => preferences.current.allowUnknownSources,
      packageDir: packages,
    );
    await addons.load();
    final player = SupervisedPlayerService(MediaKitPlayerService());
    await library.upsert(MediaItem(
      id: 'minha-midia',
      title: 'Minha mídia local',
      sourceType: MediaSourceType.local,
      source: '${Directory.current.path}/test_assets/sample.mp4',
      addedAt: DateTime(2026, 11, 1),
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
        store: store,
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      ),
    ));
    await pumpFor(tester, 1200);

    // Balão: mouse só na barra do topo.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Biblioteca')));
    await pumpFor(tester, 900);
    expect(find.text('Biblioteca'), findsOneWidget,
        reason: 'balão na barra do topo');
    await mouse.moveTo(tester.getCenter(find.byTooltip('Opções').first));
    await pumpFor(tester, 900);
    expect(
      TooltipTheme.of(tester.element(find.byTooltip('Opções').first))
          .textStyle
          ?.color
          ?.a,
      0,
      reason: 'balão invisível no cartão',
    );
    await mouse.moveTo(Offset.zero);
    await pumpFor(tester);

    // Clique direito abre o menu do cartão.
    await tester.tap(find.byType(MediaPosterCard).first,
        buttons: kSecondaryButton);
    await pumpFor(tester);
    expect(find.text('Adicionar aos favoritos'), findsOneWidget,
        reason: 'clique direito abre o menu');
    await tester.tapAt(const Offset(5, 500));
    await pumpFor(tester);

    // Instalação limpa: bloqueada, com motivo e atalho.
    await tester.tap(find.byTooltip('Add-ons'));
    await pumpFor(tester);
    await tapText(tester, 'Instalar de zip');
    expect(find.text('Instalação bloqueada'), findsOneWidget);
    await tapText(tester, 'Ativar fontes desconhecidas');
    expect(find.text('Permitir fontes desconhecidas?'), findsOneWidget);
    await tapText(tester, 'Ativar');
    expect(preferences.current.allowUnknownSources, isTrue);
    expect(find.text('Procurar pacote…'), findsOneWidget);

    // Três zips ruins: três mensagens diferentes, nada instalado.
    await readZip(tester, '$zips/kodi.zip');
    await waitFor(tester, find.textContaining('add-on do Kodi'));
    await readZip(tester, '$zips/com-codigo.zip');
    await waitFor(tester, find.textContaining('arquivo não aceito'));
    await readZip(tester, '$zips/cortado.zip');
    await waitFor(tester, find.textContaining('corrompido'));
    expect(addons.addons, isEmpty);

    // Zip válido pelo caminho: revisão completa, entra desativado.
    await readZip(tester, '$zips/olympus-teste.zip');
    await waitFor(tester, find.text('Revise antes de instalar'));
    expect(find.text('SHA-256'), findsOneWidget);
    expect(find.text('Pacote de teste'), findsOneWidget);
    await tapText(tester,
        'Entendo que esta fonte não foi verificada pelo aplicativo.');
    await tapText(tester, 'Instalar');
    await pumpFor(tester, 1000);
    const id = 'olympus.teste.pacote';
    expect(addons.getStatus(id), AddonState.inactive);
    final installedDir = addons.findById(id)!.packageDir!;
    expect(Directory(installedDir).existsSync(), isTrue);

    // Ativar: a fileira aparece e o pôster toca de verdade.
    await addons.enable(id);
    await tester.tap(find.byType(BackButton));
    await pumpFor(tester, 1500);
    await waitFor(tester, find.text('Pacote de teste'));
    final poster = find.byWidgetPredicate((widget) =>
        widget is MediaPosterCard && widget.item.title == 'Big Buck Bunny');
    await waitFor(tester, poster);
    await tester.ensureVisible(poster);
    await pumpFor(tester);
    await tester.tap(poster);
    await pumpFor(tester, 1000);
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end) &&
        player.session.position < const Duration(seconds: 3)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(player.session.status, isNot(PlaybackStatus.error));
    expect(player.session.position, greaterThan(const Duration(seconds: 2)),
        reason: 'o filme do catálogo tocou');

    // Player: mouse em cima de um botão não abre balão.
    await mouse.moveTo(tester.getCenter(find.byTooltip('Fechar')));
    await pumpFor(tester, 900);
    expect(
      TooltipTheme.of(tester.element(find.byTooltip('Fechar')))
          .textStyle
          ?.color
          ?.a,
      0,
      reason: 'balão invisível no player',
    );
    await tester.tap(find.byTooltip('Fechar'));
    await mouse.moveTo(Offset.zero);
    await pumpFor(tester, 1500);
    expect(find.text('Continuar assistindo'), findsOneWidget);

    // Fontes desligadas: o add-on segue ativo, instalar outro é bloqueado.
    await preferences
        .update(preferences.current.copyWith(allowUnknownSources: false));
    await pumpFor(tester);
    expect(addons.getStatus(id), AddonState.active);
    expect(find.text('Pacote de teste'), findsOneWidget);
    await tester.tap(find.byTooltip('Add-ons'));
    await pumpFor(tester);
    await tapText(tester, 'Instalar de zip');
    expect(find.text('Instalação bloqueada'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await pumpFor(tester);
    await preferences
        .update(preferences.current.copyWith(allowUnknownSources: true));

    // Remover: a pasta some, a mídia local fica.
    await addons.uninstall(id);
    await pumpFor(tester);
    expect(Directory(installedDir).existsSync(), isFalse);
    expect(library.findById('minha-midia'), isNotNull);

    // Zip por link: baixa por HTTP de verdade e instala.
    await tapText(tester, 'Instalar de zip');
    final url = 'http://127.0.0.1:${server.port}/olympus-teste.zip';
    final link = find.widgetWithText(TextField, 'Link do pacote');
    await tester.ensureVisible(link);
    tester.widget<TextField>(link).controller!.text = url;
    await pumpFor(tester, 100);
    await tapText(tester, 'Baixar pacote');
    await waitFor(tester, find.text('Revise antes de instalar'));
    await tapText(tester,
        'Entendo que esta fonte não foi verificada pelo aplicativo.');
    await tapText(tester, 'Instalar');
    await pumpFor(tester, 1000);
    expect(addons.getStatus(id), AddonState.inactive);
    await addons.enable(id);
    await tester.tap(find.byType(BackButton));
    await pumpFor(tester, 1500);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
