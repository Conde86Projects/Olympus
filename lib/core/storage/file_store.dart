import 'dart:convert';
import 'dart:io';

import 'package:player/core/storage/local_store.dart';

/// [LocalStore] em arquivos JSON: cada chave vira `<chave>.json` dentro de
/// um diretorio dedicado (ex. application support). Leitura corrompida
/// retorna null para o chamador iniciar vazio (spec 7, 19).
class FileLocalStore implements LocalStore {
  FileLocalStore(this.directory);

  final Directory directory;

  static final _safeKey = RegExp(r'^[a-z0-9_-]+$');

  File _fileFor(String key) {
    if (!_safeKey.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Chave de armazenamento inválida.');
    }
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return Map<String, Object?>.from(decoded as Map);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    final file = _fileFor(key);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async {
    final file = _fileFor(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        await entity.delete();
      }
    }
  }
}
