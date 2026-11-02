import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';
import 'package:player/services/video_file_listing.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/core/storage/local_store.dart';
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

/// T2: segmento Zip da instalação. Costura da Parte 2: tela de
/// instalação com preferência ligada e pacote real em arquivo.
/// T3: o mesmo fake serve bytes do link, com trava e falha
/// programáveis para exercitar progresso, cancelamento e retry.
class _FakeFetcher extends AddonFetcher {
  _FakeFetcher();

  /// Pacote servido no download; null usa o pacote de demonstração.
  Uint8List? packageBytes;

  /// Mensagem de falha imediata do download (testa erro + retry).
  String? failMessage;

  /// Trava após a primeira fatia até [downloadGate] completar;
  /// o cancelamento destrava com o motivo (testa progresso e
  /// cancelamento sem corrida).
  bool hangAfterFirstChunk = false;
  Completer<void>? downloadGate;

  int progressCalls = 0;

  /// Bytes efetivamente servidos (a revisão mostra o SHA deles).
  Uint8List? servedBytes;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    throw const AddonError.fetchFailed('fora de uso neste teste.');
  }

  @override
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    var cancelled = false;
    cancel?.then((_) => cancelled = true);
    if (failMessage != null) {
      throw AddonError.fetchFailed(failMessage!);
    }
    final bytes = packageBytes ?? packageZip();
    const slice = 32 * 1024;
    final out = <int>[];
    var first = true;
    for (var i = 0; i < bytes.length; i += slice) {
      if (cancelled) {
        throw const AddonError.fetchFailed(fetchCancelledMessage);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (cancelled) {
        throw const AddonError.fetchFailed(fetchCancelledMessage);
      }
      final end = (i + slice).clamp(0, bytes.length);
      out.addAll(bytes.sublist(i, end));
      onProgress?.call(out.length, bytes.length);
      progressCalls++;
      if (i + slice >= bytes.length) servedBytes = Uint8List.fromList(out);
      if (first && hangAfterFirstChunk) {
        first = false;
        final gate = downloadGate!;
        var open = false;
        unawaited(gate.future.then((_) => open = true));
        while (!open) {
          if (cancelled) {
            throw const AddonError.fetchFailed(fetchCancelledMessage);
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        if (cancelled) {
          throw const AddonError.fetchFailed(fetchCancelledMessage);
        }
      }
    }
    return Uint8List.fromList(out);
  }
}

Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.addFile(ArchiveFile(name, content.length, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List packageZip() {
  final manifest = demoManifestJson();
  return zipOf({
    'addon.json': utf8.encode(jsonEncode(manifest)),
    'catalog.json': utf8.encode(jsonEncode({
      'items': [
        {
          'id': 'v1',
          'title': 'Vídeo 1',
          'sourceUrl': 'https://cdn.exemplo.com/v1.mp4',
        },
        {
          'id': 'v2',
          'title': 'Vídeo 2',
          'sourceUrl': 'https://cdn.exemplo.com/v2.mp4',
        },
      ],
    })),
  });
}

class _Harness {
  _Harness(this.packages) : preferences = InMemoryPreferencesService() {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
    addons = LocalAddonService(
      InMemoryLocalStore(),
      platform: 'windows',
      fetcher: fetcher,
      packageDir: packages,
      allowUnknownSources: () => preferences.current.allowUnknownSources,
    );
  }

  final _FakeFetcher fetcher = _FakeFetcher();
  final Directory packages;
  final InMemoryPreferencesService preferences;
  late final LocalAddonService addons;
  final InMemoryLibraryService library = InMemoryLibraryService();
  final InMemoryHistoryService history = InMemoryHistoryService();
  final NoOpMediaPlayerService player = const NoOpMediaPlayerService();
  final NoOpWindowService windows = NoOpWindowService();
  final StartupGuard guard = StartupGuard(InMemoryLocalStore());

  DiagnosticsService get diagnostics => DiagnosticsService(
        store: InMemoryLocalStore(),
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      );

  Future<void> setAllowed(bool value) async {
    await preferences.update(
        preferences.current.copyWith(allowUnknownSources: value));
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 3400));
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

  Future<void> openZip(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar de zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zip'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('na TV, Procurar pacote abre o navegador próprio',
      (tester) async {
    final harness = _Harness(Directory.systemTemp);
    await harness.preferences.update(harness.preferences.current
        .copyWith(allowUnknownSources: true, tvMode: true));
    await harness.pump(tester);
    await harness.openZip(tester);

    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<FocusableButton>()?.label,
      'Procurar pacote…',
    );

    await tester.tap(find.text('Procurar pacote…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TvFileBrowserScreen), findsOneWidget);
    expect(find.text('Escolher pacote'), findsOneWidget);
  });

  test('o navegador lista só zip e pastas', () async {
    final dir = await Directory.systemTemp.createTemp('olympus-zip');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/pacote.ZIP').writeAsStringSync('x');
    File('${dir.path}/filme.mp4').writeAsStringSync('x');
    Directory('${dir.path}/pasta').createSync();

    final entries = await listFolderWithExtension(dir.path, '.zip');

    expect(entries.map((entry) => entry.name), ['pasta', 'pacote.ZIP']);
  });

  testWidgets('zip por caminho instala e mostra SHA na revisão',
      (tester) async {
    // IO sincrono no corpo: testWidgets roda em FakeAsync e IO real
    // (disco, compute) nunca completaria fora de runAsync.
    final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
    addTearDown(() => work.deleteSync(recursive: true));
    final packages =
        Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
    addTearDown(() => packages.deleteSync(recursive: true));
    final bytes = packageZip();
    final zipFile = File('${work.path}/pacote.zip');
    zipFile.writeAsBytesSync(bytes);
    final harness = _Harness(packages);
    await harness.setAllowed(true);
    await harness.pump(tester);
    await harness.openZip(tester);

    await tester.enterText(
        find.byType(TextField).first, zipFile.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Ler pacote'));
      for (var i = 0;
          i < 200 &&
              find.text('Revise antes de instalar').evaluate().isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Revise antes de instalar'), findsOneWidget);
    expect(find.textContaining(sha256.convert(bytes).toString()),
        findsOneWidget);
    expect(find.textContaining('2 itens:'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Instalar'));
      for (var i = 0;
          i < 200 &&
              find.text('Add-on instalado desativado.').evaluate().isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(
        harness.addons.getStatus('demo.catalogo'), AddonState.inactive);
    expect(find.text('Add-on instalado desativado.'), findsOneWidget);
  });

  testWidgets('zip do Kodi mostra a mensagem própria', (tester) async {
    final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
    addTearDown(() => work.deleteSync(recursive: true));
    final packages =
        Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
    addTearDown(() => packages.deleteSync(recursive: true));
    final bytes = zipOf({
      'addon.xml': utf8.encode('<addon id="x.y" version="1.0.0"></addon>'),
    });
    final zipFile = File('${work.path}/kodi.zip');
    zipFile.writeAsBytesSync(bytes);
    final harness = _Harness(packages);
    await harness.setAllowed(true);
    await harness.pump(tester);
    await harness.openZip(tester);

    await tester.enterText(
        find.byType(TextField).first, zipFile.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Ler pacote'));
      for (var i = 0;
          i < 200 &&
              find
                  .textContaining('Este é um add-on do Kodi')
                  .evaluate()
                  .isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Revise antes de instalar'), findsNothing);
    expect(
        find.textContaining('Este é um add-on do Kodi'), findsOneWidget);
    expect(harness.addons.addons, isEmpty);
  });

  testWidgets('zip sem catálogo é recusado na entrada', (tester) async {
    final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
    addTearDown(() => work.deleteSync(recursive: true));
    final packages =
        Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
    addTearDown(() => packages.deleteSync(recursive: true));
    final bytes = zipOf({
      'addon.json': utf8.encode(jsonEncode(demoManifestJson())),
    });
    final zipFile = File('${work.path}/sem-catalogo.zip');
    zipFile.writeAsBytesSync(bytes);
    final harness = _Harness(packages);
    await harness.setAllowed(true);
    await harness.pump(tester);
    await harness.openZip(tester);

    await tester.enterText(
        find.byType(TextField).first, zipFile.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Ler pacote'));
      for (var i = 0;
          i < 200 &&
              find
                  .textContaining('catalog.json ou catalogUrl')
                  .evaluate()
                  .isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Revise antes de instalar'), findsNothing);
    expect(find.textContaining('catalog.json ou catalogUrl'), findsOneWidget);
    expect(harness.addons.addons, isEmpty);
  });

  testWidgets('pacote acima de 10 MB é recusado antes de ler',
      (tester) async {
    final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
    addTearDown(() => work.deleteSync(recursive: true));
    final packages =
        Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
    addTearDown(() => packages.deleteSync(recursive: true));
    final zipFile = File('${work.path}/grande.zip');
    zipFile.writeAsBytesSync(List<int>.filled(11 * 1024 * 1024, 0));
    final harness = _Harness(packages);
    await harness.setAllowed(true);
    await harness.pump(tester);
    await harness.openZip(tester);

    await tester.enterText(
        find.byType(TextField).first, zipFile.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Ler pacote'));
      for (var i = 0;
          i < 200 &&
              find
                  .text('O pacote é grande demais (limite de 10 MB).')
                  .evaluate()
                  .isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('O pacote é grande demais (limite de 10 MB).'),
        findsOneWidget);
    expect(find.text('Revise antes de instalar'), findsNothing);
    expect(harness.addons.addons, isEmpty);
  });

  group('pacote por link (T3)', () {
    testWidgets('link baixa com progresso e chega à revisão',
        (tester) async {
      final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
      addTearDown(() => work.deleteSync(recursive: true));
      final packages =
          Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
      addTearDown(() => packages.deleteSync(recursive: true));
      final harness = _Harness(packages);
      await harness.setAllowed(true);
      await harness.pump(tester);
      await harness.openZip(tester);

      await tester.enterText(find.byType(TextField).last,
          'https://pacotes.exemplo.com/demo.zip');
      await tester.runAsync(() async {
        await tester.tap(find.text('Baixar pacote'));
        for (var i = 0;
            i < 200 &&
                find.text('Revise antes de instalar').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(find.textContaining('2 itens:'), findsOneWidget);
      expect(
          find.textContaining(
              sha256.convert(harness.fetcher.servedBytes!).toString()),
          findsOneWidget);
      expect(harness.fetcher.progressCalls, greaterThan(0));
    });

    testWidgets('download mostra progresso e cancela', (tester) async {
      final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
      addTearDown(() => work.deleteSync(recursive: true));
      final packages =
          Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
      addTearDown(() => packages.deleteSync(recursive: true));
      final harness = _Harness(packages);
      harness.fetcher.hangAfterFirstChunk = true;
      harness.fetcher.downloadGate = Completer<void>();
      await harness.setAllowed(true);
      await harness.pump(tester);
      await harness.openZip(tester);

      await tester.enterText(find.byType(TextField).last,
          'https://pacotes.exemplo.com/demo.zip');
      await tester.runAsync(() async {
        await tester.tap(find.text('Baixar pacote'));
        for (var i = 0;
            i < 200 &&
                find.textContaining('Baixando').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        expect(find.byKey(const Key('downloadProgress')), findsOneWidget);
        await tester.tap(find.text('Cancelar download'));
        for (var i = 0;
            i < 200 && find.text('Download cancelado.').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Download cancelado.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text('Revise antes de instalar'), findsNothing);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('erro no download mostra tentar de novo', (tester) async {
      final work = Directory.systemTemp.createTempSync('olympus-zip-tela-');
      addTearDown(() => work.deleteSync(recursive: true));
      final packages =
          Directory.systemTemp.createTempSync('olympus-pacotes-tela-');
      addTearDown(() => packages.deleteSync(recursive: true));
      final harness = _Harness(packages);
      harness.fetcher.failMessage = 'Falha simulada.';
      await harness.setAllowed(true);
      await harness.pump(tester);
      await harness.openZip(tester);

      await tester.enterText(find.byType(TextField).last,
          'https://pacotes.exemplo.com/demo.zip');
      await tester.runAsync(() async {
        await tester.tap(find.text('Baixar pacote'));
        for (var i = 0;
            i < 200 && find.text('Falha simulada.').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Falha simulada.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);

      harness.fetcher.failMessage = null;
      await tester.runAsync(() async {
        await tester.tap(find.text('Tentar de novo'));
        for (var i = 0;
            i < 200 &&
                find.text('Revise antes de instalar').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(find.textContaining('2 itens:'), findsOneWidget);
    });
  });
}
