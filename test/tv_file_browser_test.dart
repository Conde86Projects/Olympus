import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';
import 'package:player/services/video_file_listing.dart';

Future<List<BrowserEntry>> _fakeList(String path) async {
  if (path == '/sdcard/Download') {
    return const [
      BrowserEntry(
          name: 'filmes', path: '/sdcard/Download/filmes', isDirectory: true),
      BrowserEntry(
          name: 'clip.mp4',
          path: '/sdcard/Download/clip.mp4',
          isDirectory: false),
    ];
  }
  if (path == '/sdcard/Download/filmes') {
    return const [
      BrowserEntry(
          name: 'longa.mkv',
          path: '/sdcard/Download/filmes/longa.mkv',
          isDirectory: false),
    ];
  }
  return const [];
}

String? _picked;
bool _popped = false;

Future<void> _openBrowser(WidgetTester tester) async {
  _picked = null;
  _popped = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            _picked = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => TvFileBrowserScreen(
                  roots: const ['/sdcard/Download'],
                  list: _fakeList,
                  ensureAccess: () async => true,
                ),
              ),
            );
            _popped = true;
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('OK num vídeo devolve o caminho escolhido', (tester) async {
    await _openBrowser(tester);
    await tester.tap(find.text('Download/'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('clip.mp4'));
    await tester.pumpAndSettle();
    expect(_picked, '/sdcard/Download/clip.mp4');
  });

  testWidgets('OK numa pasta entra nela; Voltar sobe e na raiz fecha',
      (tester) async {
    await _openBrowser(tester);
    await tester.tap(find.text('Download/'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('filmes/'));
    await tester.pumpAndSettle();
    expect(find.text('longa.mkv'), findsOneWidget);

    // Voltar sobe para Download; depois para a lista de pastas de partida.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(_popped, isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Download/'), findsOneWidget);
    expect(_popped, isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(_popped, isTrue);
    expect(_picked, isNull);
  });

  testWidgets('pasta vazia explica o que fazer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TvFileBrowserScreen(
        roots: const [],
        list: _fakeList,
        ensureAccess: () async => true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nenhum vídeo'), findsOneWidget);
  });
}
