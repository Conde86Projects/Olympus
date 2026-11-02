import 'dart:convert';
import 'dart:io';

import 'package:player/core/storage/local_store.dart';

/// [LocalStore] em arquivos JSON: cada chave vira `<chave>.json` dentro de
/// um diretorio dedicado (ex. application support). Leitura corrompida
/// retorna null para o chamador iniciar vazio (spec 7, 19).
///
/// Gravar é atômico: o JSON vai para um temporário e só no fim substitui o
/// arquivo. Uma queda no meio deixa o arquivo anterior inteiro. Gravações
/// da mesma chave rodam uma por vez, na ordem pedida.
class FileLocalStore implements LocalStore {
  FileLocalStore(this.directory);

  final Directory directory;

  static final _safeKey = RegExp(r'^[a-z0-9_-]+$');
  static const _tempSuffix = '.tmp';

  File _fileFor(String key) {
    if (!_safeKey.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Chave de armazenamento inválida.');
    }
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  /// Última operação pendente de cada chave.
  final _pending = <String, Future<void>>{};

  /// Enfileira [operation] depois da anterior da mesma chave. A falha de
  /// uma gravação vai para quem a pediu e não trava as seguintes.
  Future<void> _enqueue(String key, Future<void> Function() operation) {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => operation());
    _pending[key] = next;
    return next.whenComplete(() {
      if (identical(_pending[key], next)) _pending.remove(key);
    });
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final file = _fileFor(key);
    // Lê depois do que já foi pedido para gravar nesta chave.
    await _pending[key]?.catchError((Object _) {});
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) {
    final file = _fileFor(key);
    // Serializa agora: quem chamou pode mudar o mapa depois.
    final bytes = utf8.encode(jsonEncode(value));
    return _enqueue(key, () async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}$_tempSuffix');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    });
  }

  @override
  Future<void> remove(String key) {
    final file = _fileFor(key);
    return _enqueue(key, () async {
      if (await file.exists()) await file.delete();
    });
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      for (final pending in _pending.values.toList())
        pending.catchError((Object _) {}),
    ]);
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File &&
          (entity.path.endsWith('.json') ||
              entity.path.endsWith('.json$_tempSuffix'))) {
        await entity.delete();
      }
    }
  }
}
