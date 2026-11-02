import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/storage/file_store.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/persistent_history_service.dart';
import 'package:player/services/persistent_library_service.dart';
import 'package:player/services/shared_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItem _item(String id) => MediaItem(
      id: id,
      title: 'Vídeo $id',
      sourceType: MediaSourceType.local,
      source: 'C:\\videos\\$id.mp4',
      duration: const Duration(minutes: 10),
      lastPosition: const Duration(minutes: 3),
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('FileLocalStore', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('player_store_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('grava, le e remove documentos', () async {
      final store = FileLocalStore(temp);
      expect(await store.read('library'), isNull);

      await store.write('library', {
        'items': ['a']
      });
      expect(await store.read('library'), {
        'items': ['a']
      });

      await store.remove('library');
      expect(await store.read('library'), isNull);
    });

    test('leitura corrompida retorna null', () async {
      final store = FileLocalStore(temp);
      final file = File('${temp.path}${Platform.pathSeparator}broken.json');
      await file.writeAsString('{json invalido');
      expect(await store.read('broken'), isNull);
    });

    test('falha no meio da gravação preserva o arquivo anterior', () async {
      final store = FileLocalStore(temp);
      await store.write('library', {'versao': 1});
      // O temporário vira pasta: a escrita falha antes de trocar o arquivo.
      await Directory('${temp.path}${Platform.pathSeparator}library.json.tmp')
          .create();

      await expectLater(store.write('library', {'versao': 2}), throwsA(anything));

      expect(await store.read('library'), {'versao': 1});
    });

    test('gravações seguidas terminam na última, com JSON inteiro', () async {
      final store = FileLocalStore(temp);

      await Future.wait([
        for (var i = 0; i < 40; i++)
          store.write('history', {'n': i, 'recheio': 'x' * 20000}),
      ]);

      expect((await store.read('history'))!['n'], 39);
      final tmp =
          File('${temp.path}${Platform.pathSeparator}history.json.tmp');
      expect(tmp.existsSync(), isFalse);
    });

    test('leitura logo depois de gravar vê o valor novo', () async {
      final store = FileLocalStore(temp);

      final write = store.write('prefs', {'a': 1});
      final read = await store.read('prefs');
      await write;

      expect(read, {'a': 1});
    });

    test('JSON que não é objeto e bytes inválidos retornam null', () async {
      final store = FileLocalStore(temp);
      final sep = Platform.pathSeparator;
      await File('${temp.path}${sep}lista.json').writeAsString('[1, 2]');
      await File('${temp.path}${sep}bytes.json')
          .writeAsBytes([0xFF, 0xFE, 0x00]);

      expect(await store.read('lista'), isNull);
      expect(await store.read('bytes'), isNull);
    });

    test('limpar leva o temporário junto', () async {
      final store = FileLocalStore(temp);
      final sep = Platform.pathSeparator;
      await store.write('library', {'a': 1});
      final tmp = File('${temp.path}${sep}library.json.tmp');
      await tmp.writeAsString('sobra de uma queda');

      await store.clear();

      expect(await store.read('library'), isNull);
      expect(tmp.existsSync(), isFalse);
    });

    test('rejeita chave insegura', () async {
      final store = FileLocalStore(temp);
      expect(() => store.read('../fora'), throwsArgumentError);
    });
  });

  group('PersistentLibraryService', () {
    test('sobrevive a reinicializacao', () async {
      final store = InMemoryLocalStore();
      final first = PersistentLibraryService(store);
      await first.load();
      await first.upsert(_item('1'));
      await first.toggleFavorite('1');

      final second = PersistentLibraryService(store);
      await second.load();
      expect(second.items, hasLength(1));
      expect(second.items.single.isFavorite, isTrue);
      expect(second.items.single.lastPosition,
          const Duration(minutes: 3));
    });

    test('ignora item corrompido e mantem os validos', () async {
      final store = InMemoryLocalStore();
      await store.write('library', {
        'items': [
          _item('ok').toMap(),
          {'id': 'ruim'}, // sem campos obrigatorios
        ],
      });
      final library = PersistentLibraryService(store);
      await library.load();
      expect(library.items.map((i) => i.id), ['ok']);
    });

    test('mesclagem por source aplica miniatura entrante', () async {
      // Regressao: a geracao de fundo fazia upsert com thumbnail e o
      // merge por source descartava (null persistido para sempre).
      final store = InMemoryLocalStore();
      final library = PersistentLibraryService(store);
      await library.load();
      final saved = await library.upsert(_item('1'));
      expect(saved.thumbnailPath, isNull);

      final withThumb = await library.upsert(
        _item('novo-id').copyWith(
          source: r'C:\videos\1.mp4',
          thumbnailPath: () => '/t/1.jpg',
        ),
      );
      expect(withThumb.id, '1'); // reaproveita o existente
      expect(withThumb.thumbnailPath, '/t/1.jpg');

      final reloaded = PersistentLibraryService(store);
      await reloaded.load();
      expect(reloaded.items.single.thumbnailPath, '/t/1.jpg');
    });

    test('mesclagem preserva miniatura quando entrante e null', () async {
      final store = InMemoryLocalStore();
      final library = PersistentLibraryService(store);
      await library.load();
      await library.upsert(
        _item('1').copyWith(thumbnailPath: () => '/t/1.jpg'),
      );
      final merged = await library
          .upsert(_item('outro-id').copyWith(source: r'C:\videos\1.mp4'));
      expect(merged.id, '1');
      expect(merged.thumbnailPath, '/t/1.jpg');
    });
  });

  group('PersistentHistoryService', () {
    test('sobrevive a reinicializacao', () async {
      final store = InMemoryLocalStore();
      final first = PersistentHistoryService(store);
      await first.load();
      await first.record(HistoryEntry(
        mediaId: '1',
        accessedAt: DateTime(2026, 3, 3),
        position: const Duration(seconds: 90),
        percentWatched: 0.15,
      ));

      final second = PersistentHistoryService(store);
      await second.load();
      expect(second.entries, hasLength(1));
      expect(second.entries.single.position,
          const Duration(seconds: 90));
    });
  });

  group('SharedPreferencesPreferencesService', () {
    test('carrega padroes, atualiza e persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesPreferencesService();
      await prefs.load();
      expect(prefs.current.theme, AppThemeMode.dark);

      await prefs.update(
          prefs.current.copyWith(alwaysOnTop: true, defaultSpeed: 1.5));
      expect(prefs.current.alwaysOnTop, isTrue);

      final reopened = SharedPreferencesPreferencesService();
      await reopened.load();
      expect(reopened.current.alwaysOnTop, isTrue);
      expect(reopened.current.defaultSpeed, 1.5);
    });

    test('json corrompido volta aos padroes', () async {
      SharedPreferences.setMockInitialValues(
          {'player.preferences': '{invalido'});
      final prefs = SharedPreferencesPreferencesService();
      await prefs.load();
      expect(prefs.current.alwaysOnTop, isFalse);
    });
  });
}
