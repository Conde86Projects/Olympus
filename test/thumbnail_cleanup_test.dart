import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('player/thumbnails');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  MediaItem localItem(String id, String source) => MediaItem(
        id: id,
        title: 'Video $id',
        sourceType: MediaSourceType.local,
        source: source,
        addedAt: DateTime(2026, 1, 1),
      );

  /// Espera o arquivo sumir. A limpeza roda em segundo plano para nao
  /// travar a remocao (ver InMemoryLibraryService.remove/clear), entao
  /// o teste aguarda em vez de exigir efeito imediato.
  Future<void> expectGoneSoon(File file) async {
    for (var i = 0; i < 100 && file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(file.existsSync(), isFalse);
  }

  Future<void> expectNoJpgSoon(Directory dir) async {
    for (var i = 0;
        i < 100 &&
            dir.listSync().where((e) => e.path.endsWith('.jpg')).isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(dir.listSync().where((e) => e.path.endsWith('.jpg')), isEmpty);
  }

  group('limpeza de miniaturas orfas (remove/clear)', () {
    test('gera -> remove o item -> o jpg some, a midia fica', () async {
      final tmp = await Directory.systemTemp.createTemp('thumb_cleanup_test');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1, 2, 3]);
      messenger.setMockMethodCallHandler(
          channel, (call) async => Uint8List.fromList([9, 9, 9]));

      final thumbsDir =
          await Directory('${tmp.path}/thumbs').create(recursive: true);
      final thumbs = ThumbnailService(directoryProvider: () async => thumbsDir);
      final library = InMemoryLibraryService(thumbnailService: thumbs);

      final saved = await library.upsert(localItem('v1', source.path));
      final path = await thumbs.generateFor(saved);
      expect(path, endsWith('v1.jpg'));
      expect(File(path!).existsSync(), isTrue);

      await library.remove(saved.id);

      expect(library.findById(saved.id), isNull);
      await expectGoneSoon(File(path));
      // Nunca apaga a midia de origem.
      expect(source.existsSync(), isTrue);
    });

    test('remover item sem miniatura e id ausente eh no-op', () async {
      final tmp = await Directory.systemTemp.createTemp('thumb_noop_test');
      addTearDown(() => tmp.delete(recursive: true));
      final library = InMemoryLibraryService(
          thumbnailService:
              ThumbnailService(directoryProvider: () async => tmp));

      // Id que nunca existiu: sem throw.
      await library.remove('fantasma');

      final source = File('${tmp.path}/in.mp4')..writeAsBytesSync([1]);
      await library.upsert(localItem('v2', source.path));
      // Sem jpg gerado: sai do mapa sem throw.
      await library.remove('v2');
      expect(library.findById('v2'), isNull);
      expect(source.existsSync(), isTrue);
    });

    test('deleteFor direto: arquivo ausente eh no-op', () async {
      final tmp = await Directory.systemTemp.createTemp('thumb_delnoop_test');
      addTearDown(() => tmp.delete(recursive: true));

      await ThumbnailService.deleteFor('fantasma',
          service: ThumbnailService(directoryProvider: () async => tmp));
    });

    test('deleteFor direto: provedor que falha eh no-op', () async {
      Future<Directory> fail() async => throw StateError('sem disco');
      await ThumbnailService.deleteFor('v1',
          service: ThumbnailService(directoryProvider: fail));
    });

    test('clear apaga os jpgs de todos os itens', () async {
      final tmp = await Directory.systemTemp.createTemp('thumb_clear_test');
      addTearDown(() => tmp.delete(recursive: true));
      messenger.setMockMethodCallHandler(
          channel, (call) async => Uint8List.fromList([7]));
      final thumbsDir =
          await Directory('${tmp.path}/thumbs').create(recursive: true);
      final thumbs = ThumbnailService(directoryProvider: () async => thumbsDir);
      final library = InMemoryLibraryService(thumbnailService: thumbs);

      for (final id in ['a', 'b']) {
        final source = File('${tmp.path}/$id.mp4')..writeAsBytesSync([1]);
        final saved = await library.upsert(localItem(id, source.path));
        await thumbs.generateFor(saved);
      }
      expect(
          thumbsDir.listSync().where((e) => e.path.endsWith('.jpg')),
          hasLength(2));

      await library.clear();

      expect(library.items, isEmpty);
      await expectNoJpgSoon(thumbsDir);
    });
  });
}
