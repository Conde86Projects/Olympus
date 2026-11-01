import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
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

/// Fake com corpos mutaveis: permite simular recuperacao (falha e
/// depois sucesso na nova tentativa).
class _FakeFetcher extends AddonFetcher {
  _FakeFetcher(this.bodies, {this.byteBodies = const {}});

  final Map<String, String> bodies;
  final Map<String, Uint8List> byteBodies;

  @override
  Future<String> fetchText(String url, {Map<String, String> headers = const {}}) async {
    final body = bodies[url];
    if (body == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    return body;
  }

  @override
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    final bytes = byteBodies[url];
    if (bytes == null) {
      throw const AddonError.fetchFailed('Não foi possível buscar.');
    }
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }
}

class _Harness {
  _Harness(
      {Map<String, String>? bodies,
      Map<String, Uint8List>? byteBodies,
      Directory? packageDir})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(
          InMemoryLocalStore(),
          // Plataforma fixa: os estados da listagem não dependem do
          // aparelho que roda o teste.
          platform: 'windows',
          fetcher: _FakeFetcher(bodies ?? {},
              byteBodies: byteBodies ?? {}),
          packageDir: packageDir,
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

  Future<void> openRepos(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add-ons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Repositórios'));
    await tester.pumpAndSettle();
  }

  Future<void> addRepo(
    WidgetTester tester, {
    required String name,
    required String origin,
    bool trusted = false,
  }) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'Nome'), name);
    await tester.enterText(
        find.widgetWithText(TextField, 'Endereço da listagem'), origin);
    if (trusted) {
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
  }
}

String listingJson() => jsonEncode({
      'addons': [demoManifestJson()],
    });

void main() {
  group('tela Repositórios', () {
    testWidgets('lista tem entrada para repositórios', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      expect(find.text('Adicionar repositório'), findsOneWidget);
      expect(find.text('Nenhum repositório cadastrado'), findsOneWidget);
    });

    testWidgets('adiciona repositório válido e lista', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      expect(find.text('Comunidade'), findsOneWidget);
      expect(find.text('exemplo.com'), findsOneWidget);
      expect(find.text('Não verificado'), findsOneWidget);
      expect(harness.addons.repositories, hasLength(1));
    });

    testWidgets('endereço inválido mostra erro e não cadastra',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Ruim',
        origin: 'não é url',
      );

      expect(find.text('Endereço do repositório inválido (use http/https).'),
          findsOneWidget);
      expect(harness.addons.repositories, isEmpty);
    });

    testWidgets('duplicado é rejeitado', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Um',
        origin: 'https://exemplo.com/repo.json',
      );
      await harness.addRepo(
        tester,
        name: 'Dois',
        origin: 'https://exemplo.com/repo.json',
      );

      expect(find.text('Este endereço já está cadastrado.'),
          findsOneWidget);
      expect(harness.addons.repositories, hasLength(1));
    });

    testWidgets('marca confiável aparece na lista', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);

      await harness.addRepo(
        tester,
        name: 'Oficial',
        origin: 'https://exemplo.com/oficial.json',
        trusted: true,
      );

      // Titulo do switch do formulario + marca na linha do repositorio.
      expect(find.text('Confiável'), findsNWidgets(2));
      expect(find.text('Não verificado'), findsNothing);
      expect(harness.addons.repositories.single.trusted, isTrue);
    });

    testWidgets('navegar lista itens e instala pelo fluxo de revisão',
        (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
        trusted: true,
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      final installed = harness.addons.findById('demo.catalogo')!;
      expect(installed.originTrusted, isTrue);
      expect(find.text('Instalado'), findsOneWidget);
    });

    testWidgets('cancelar na revisão volta ao repositório', (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Catálogo Demo'), findsOneWidget);
      expect(harness.addons.addons, isEmpty);
    });

    testWidgets('repositório fora do ar mostra fonte indisponível',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Fora do ar',
        origin: 'https://exemplo.com/off.json',
      );

      await tester.tap(find.text('Fora do ar'));
      await tester.pumpAndSettle();

      expect(find.text('Fonte indisponível no momento.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('nova tentativa recupera após falha', (tester) async {
      final bodies = <String, String>{};
      final harness = _Harness(bodies: bodies);
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Instável',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Instável'));
      await tester.pumpAndSettle();
      expect(find.text('Fonte indisponível no momento.'), findsOneWidget);

      bodies['https://exemplo.com/repo.json'] = listingJson();
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);
    });

    testWidgets('remover pede confirmação e apaga só o cadastro',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Sair',
        origin: 'https://exemplo.com/sair.json',
      );

      await tester.tap(find.byTooltip('Remover repositório'));
      await tester.pumpAndSettle();
      expect(find.text('Remover repositório?'), findsOneWidget);

      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Sair'), findsNothing);
      expect(harness.addons.repositories, isEmpty);
    });

    testWidgets('voltar da navegação retorna à lista', (tester) async {
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': listingJson(),
      });
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
      );

      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo Demo'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar repositório'), findsOneWidget);
      expect(find.text('Catálogo Demo'), findsNothing);
    });
  });

  group('estados do item (T4)', () {
    Uint8List packageZipBytes() {
      final archive = Archive();
      final manifest = utf8.encode(jsonEncode(demoManifestJson()));
      archive.addFile(ArchiveFile('addon.json', manifest.length, manifest));
      final catalog = utf8.encode(jsonEncode({
        'items': [
          {
            'id': 'v1',
            'title': 'Vídeo 1',
            'sourceUrl': 'https://cdn.exemplo.com/v1.mp4',
          },
        ],
      }));
      archive.addFile(ArchiveFile('catalog.json', catalog.length, catalog));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    String packageListing(
      Uint8List zipBytes, {
      String? version,
      List<String>? platforms,
    }) {
      return jsonEncode({
        'addons': [
          {
            ...demoManifestJson(version: version ?? '1.0.0'),
            if (platforms != null) 'supportedPlatforms': platforms,
            'packageUrl': 'https://exemplo.com/demo.zip',
            'sha256': sha256.convert(zipBytes).toString(),
          },
        ],
      });
    }

    Future<void> openListing(WidgetTester tester, _Harness harness) async {
      await harness.pump(tester);
      await harness.openRepos(tester);
      await harness.addRepo(
        tester,
        name: 'Comunidade',
        origin: 'https://exemplo.com/repo.json',
        trusted: true,
      );
      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
    }

    testWidgets('disponível mostra ícone, texto e botão instalar',
        (tester) async {
      final zip = packageZipBytes();
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': packageListing(zip),
      });
      await openListing(tester, harness);

      expect(find.text('Disponível'), findsOneWidget);
      expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
      expect(find.text('Instalar'), findsOneWidget);
    });

    testWidgets('instalado mostra estado sem botão', (tester) async {
      final zip = packageZipBytes();
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json': packageListing(zip),
      });
      await harness.addons.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: true,
      );
      await openListing(tester, harness);

      expect(find.text('Instalado'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Instalar'), findsNothing);
    });

    testWidgets('atualização disponível para versão mais nova',
        (tester) async {
      final zip = packageZipBytes();
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json':
            packageListing(zip, version: '2.0.0'),
      });
      await harness.addons.install(
        AddonManifest.fromMap(demoManifestJson()),
        originTrusted: true,
      );
      await openListing(tester, harness);

      expect(find.text('Atualização disponível'), findsOneWidget);
      expect(find.byIcon(Icons.system_update), findsOneWidget);
      expect(find.text('Instalar'), findsNothing);
    });

    testWidgets('não compatível esconde o botão instalar', (tester) async {
      final zip = packageZipBytes();
      final harness = _Harness(bodies: {
        'https://exemplo.com/repo.json':
            packageListing(zip, platforms: ['android']),
      });
      await openListing(tester, harness);

      expect(find.text('Não compatível'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.text('Instalar'), findsNothing);
    });

    testWidgets('instala pacote com checksum conferido', (tester) async {
      final zip = packageZipBytes();
      final expectedSha = sha256.convert(zip).toString();
      final packages =
          Directory.systemTemp.createTempSync('olympus-repos-');
      addTearDown(() {
        if (packages.existsSync()) packages.deleteSync(recursive: true);
      });
      final harness = _Harness(
        bodies: {'https://exemplo.com/repo.json': packageListing(zip)},
        byteBodies: {'https://exemplo.com/demo.zip': zip},
        packageDir: packages,
      );
      await openListing(tester, harness);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();
      expect(find.text('Revise antes de instalar'), findsOneWidget);
      expect(find.text(expectedSha), findsOneWidget);

      // IO real (compute, disco) so completa em runAsync; o padrao e
      // o mesmo da instalacao de zip (test/addon_package_install_test.dart).
      await tester.runAsync(() async {
        await tester.tap(find.text('Instalar'));
        for (var i = 0;
            i < 200 &&
                find
                    .text('Add-on instalado desativado.')
                    .evaluate()
                    .isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      final installed = harness.addons.findById('demo.catalogo')!;
      expect(installed.packageOrigin, AddonPackageOrigin.repository);
      expect(installed.packageSha256, expectedSha);
      expect(find.text('Add-on instalado desativado.'), findsOneWidget);
      expect(find.text('Instalado'), findsOneWidget);
    });
  });
}
