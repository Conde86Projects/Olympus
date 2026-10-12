import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/thumbnail_service.dart';
import 'package:player/widgets/media_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('player/thumbnails');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  MediaItem localItem(String source) => MediaItem(
        id: 'v1',
        title: 'Vídeo',
        sourceType: MediaSourceType.local,
        source: source,
        addedAt: DateTime(2026, 1, 1),
      );

  group('ThumbnailService (spec 15.1)', () {
    test('grava os bytes do nativo e devolve o caminho', () async {
      final tmp =
          await Directory.systemTemp.createTemp('thumb_service_test');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1, 2, 3]);
      messenger.setMockMethodCallHandler(
          channel, (call) async => Uint8List.fromList([9, 9, 9]));

      final service =
          ThumbnailService(directoryProvider: () async => tmp);
      final path = await service.generateFor(localItem(source.path));

      expect(path, '${tmp.path}${Platform.pathSeparator}v1.jpg');
      expect(File(path!).readAsBytesSync(), [9, 9, 9]);
    });

    test('repasse os argumentos de frame ao nativo', () async {
      final tmp =
          await Directory.systemTemp.createTemp('thumb_args_test');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1]);
      var seen = <String, Object?>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = Map<String, Object?>.from(call.arguments as Map);
        return Uint8List.fromList([7]);
      });

      await ThumbnailService(directoryProvider: () async => tmp)
          .generateFor(localItem(source.path),
              positionMs: 1500, maxWidth: 160);

      expect(seen['path'], source.path);
      expect(seen['positionMs'], 1500);
      expect(seen['maxWidth'], 160);
    });

    test('link não gera nem chama o channel', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(
          channel, (call) async => calls++);
      final item = MediaItem(
        id: 'u1',
        title: 'Link',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/v.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      expect(
          await ThumbnailService(
                  directoryProvider: () async => Directory.systemTemp)
              .generateFor(item),
          isNull);
      expect(calls, 0);
    });

    test('arquivo ausente não gera nem chama o channel', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(
          channel, (call) async => calls++);
      expect(
          await ThumbnailService(
                  directoryProvider: () async => Directory.systemTemp)
              .generateFor(localItem('/nao/existe.mp4')),
          isNull);
      expect(calls, 0);
    });

    test('nativo null, erro ou sem channel vira null', () async {
      final tmp =
          await Directory.systemTemp.createTemp('thumb_null_test');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1]);
      final service =
          ThumbnailService(directoryProvider: () async => tmp);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await service.generateFor(localItem(source.path)), isNull);

      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'X'));
      expect(await service.generateFor(localItem(source.path)), isNull);

      messenger.setMockMethodCallHandler(channel, null);
      expect(await service.generateFor(localItem(source.path)), isNull);

      // Nada gravado: só o in.mp4 de entrada segue no diretório.
      expect(
          tmp.listSync().where((e) => e.path.endsWith('.jpg')), isEmpty);
    });
  });

  group('ThumbnailService.backfill', () {
    test('gera e persiste quando falta', () async {
      final tmp = await Directory.systemTemp.createTemp('thumb_bf');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1]);
      messenger.setMockMethodCallHandler(
          channel, (call) async => Uint8List.fromList([5, 5]));
      final library = InMemoryLibraryService();
      final saved = await library.upsert(localItem(source.path));

      await ThumbnailService.backfill(
        library,
        saved,
        service: ThumbnailService(directoryProvider: () async => tmp),
      );

      final stored = library.findById(saved.id)!;
      expect(stored.thumbnailPath, endsWith('v1.jpg'));
      expect(File(stored.thumbnailPath!).existsSync(), isTrue);
    });

    test('não-op quando já tem miniatura ou é link', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(
          channel, (call) async => calls++);
      final library = InMemoryLibraryService();
      await library.upsert(
        localItem('/a.mp4').copyWith(thumbnailPath: () => '/t/v1.jpg'),
      );
      await ThumbnailService.backfill(
          library, localItem('/a.mp4'));
      final url = MediaItem(
        id: 'u1',
        title: 'Link',
        sourceType: MediaSourceType.url,
        source: 'https://exemplo.com/v.mp4',
        addedAt: DateTime(2026, 1, 1),
      );
      await library.upsert(url);
      await ThumbnailService.backfill(library, url);
      expect(calls, 0);
    });

    test('consulta o armazenado (cópia da rota pode estar obsoleta)',
        () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(
          channel, (call) async => calls++);
      final library = InMemoryLibraryService();
      // Armazenado TEM thumb; cópia passada NÃO (obsoleta).
      await library.upsert(
        localItem('/a.mp4').copyWith(thumbnailPath: () => '/t/v1.jpg'),
      );
      await ThumbnailService.backfill(
          library, localItem('/a.mp4'));
      expect(calls, 0);
    });
  });

  group('MediaItem.thumbnailPath', () {
    test('copyWith define e limpa; round-trip preserva', () {
      final base = localItem('/a.mp4');
      expect(base.thumbnailPath, isNull);
      final withThumb =
          base.copyWith(thumbnailPath: () => '/t/v1.jpg');
      expect(withThumb.thumbnailPath, '/t/v1.jpg');
      expect(MediaItem.fromMap(withThumb.toMap()).thumbnailPath,
          '/t/v1.jpg');
      expect(
          withThumb.copyWith(thumbnailPath: () => null).thumbnailPath,
          isNull);
    });
  });

  group('MediaCard miniatura', () {
    testWidgets('sem thumbnail mostra o placeholder', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MediaCard(item: localItem('/a.mp4'))),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('com thumbnail usa o builder injetado', (tester) async {
      // Sem decode real: Image.file trava o flutter test neste
      // ambiente Windows (repro mínima pura também trava). O builder
      // prova a ramificação; o default é inspecionado sem pump.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaCard(
                item: localItem('/a.mp4')
                    .copyWith(thumbnailPath: () => '/t/v1.jpg'),
                thumbnailBuilder: (path) =>
                    SizedBox(key: Key(path), width: 96, height: 56))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('/t/v1.jpg')), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    test('default usa Image.file com fallback de erro', () {
      final widget = MediaCard.defaultThumbnailImage('/t/v1.jpg');
      expect(widget, isA<Image>());
      final image = widget as Image;
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, '/t/v1.jpg');
      expect(image.fit, BoxFit.cover);
      expect(image.errorBuilder, isNotNull);
    });
  });
}
