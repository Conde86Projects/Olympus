import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_manifest.dart';

/// Limites do pacote zip (T2, registrados no ADR-0004).
abstract final class AddonPackageLimits {
  /// Teto do arquivo compactado.
  static const maxCompressedBytes = 10 * 1024 * 1024;

  /// Teto do total descompactado, verificado nos bytes reais extraídos,
  /// sem confiar no tamanho declarado no zip.
  static const maxUncompressedBytes = 30 * 1024 * 1024;

  /// Teto de entradas (só arquivos; pastas são estrutura).
  static const maxEntries = 16;

  /// Teto do ícone e da fanart.
  static const maxIconBytes = 1024 * 1024;
  static const maxFanartBytes = 5 * 1024 * 1024;
}

/// Pacote de add-on validado: só dados, sem código. A interface é
/// pequena de propósito; os nomes podem mudar, a forma não (T2).
class AddonPackage {
  const AddonPackage({
    required this.manifest,
    required this.sha256,
    this.catalogJson,
    this.catalogItemCount,
    this.catalogSample = const [],
    this.icon,
    this.fanart,
  });

  final AddonManifest manifest;

  /// SHA-256 dos bytes originais do zip, para conferir com a origem.
  final String sha256;

  /// Catálogo embutido (texto do catalog.json), ou null quando o
  /// manifesto aponta um catalogUrl remoto.
  final String? catalogJson;
  final int? catalogItemCount;

  /// Primeiros títulos do catálogo (no máximo 5), para a revisão.
  final List<String> catalogSample;
  final Uint8List? icon;
  final Uint8List? fanart;
}

/// Lê e valida os bytes de um zip, devolvendo o pacote ou um
/// [AddonError] com o motivo. Parse puro: rede, disco e tela ficam
/// fora. Roda fora da thread da interface via `compute` no serviço.
AddonPackage readAddonPackage(Uint8List zipBytes) {
  if (zipBytes.length > AddonPackageLimits.maxCompressedBytes) {
    throw const AddonError.invalidManifest(
      'O pacote é grande demais (limite de 10 MB).',
    );
  }
  if (_hasEncryptedEntry(zipBytes)) {
    throw const AddonError.invalidManifest(
      'O pacote tem entrada criptografada, que o Olympus não abre.',
    );
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw const AddonError.invalidManifest(
      'O pacote está corrompido ou não é um zip válido.',
    );
  }
  final files = [for (final f in archive.files) if (f.isFile) f];
  if (files.isEmpty) {
    throw const AddonError.invalidManifest(
      'O pacote está corrompido ou não é um zip válido.',
    );
  }
  if (_isKodiPackage(files)) {
    throw const AddonError.invalidManifest(
      'Este é um add-on do Kodi. Ele traz código que o Olympus não executa, por isso não pode ser instalado.',
    );
  }
  if (files.length > AddonPackageLimits.maxEntries) {
    throw const AddonError.invalidManifest(
      'O pacote tem entradas demais (limite de 16).',
    );
  }
  for (final file in files) {
    if (_hasBadPath(file.name)) {
      throw AddonError.invalidManifest(
        'O pacote tem um caminho inválido: "${file.name}".',
      );
    }
    if (file.isSymbolicLink || _isSymlinkMode(file.mode)) {
      throw const AddonError.invalidManifest(
        'O pacote tem link simbólico, que o Olympus não abre.',
      );
    }
  }
  if (extractedBytesTotal(files) > AddonPackageLimits.maxUncompressedBytes) {
    throw const AddonError.invalidManifest(
      'O pacote passa do limite descompactado (30 MB).',
    );
  }
  final names = _stripSingleRoot(files.map((f) => f.name).toList());
  if (names == null) {
    throw const AddonError.invalidManifest(
      'O pacote mistura arquivos da raiz com pasta.',
    );
  }
  final byName = indexPackageFiles(files, names);
  final manifest = _readManifest(byName['addon.json']!);
  final catalogFile = byName['catalog.json'];
  final hasRemoteCatalog =
      manifest.catalogUrl != null && manifest.catalogUrl!.isNotEmpty;
  if (catalogFile == null && !hasRemoteCatalog) {
    throw const AddonError.invalidManifest(
      'O pacote precisa trazer catalog.json ou catalogUrl no manifesto.',
    );
  }
  final catalog =
      catalogFile == null ? null : _readCatalog(catalogFile);
  return AddonPackage(
    manifest: manifest,
    sha256: sha256.convert(zipBytes).toString(),
    catalogJson: catalog?.$1,
    catalogItemCount: catalog?.$2,
    catalogSample: catalog?.$3 ?? const [],
    icon: _readImage(byName['icon.png'], 'O ícone', AddonPackageLimits.maxIconBytes),
    fanart: _readImage(
        byName['fanart.jpg'], 'A fanart', AddonPackageLimits.maxFanartBytes),
  );
}

/// Razão de caminho inseguro, ou null quando o nome é aceitável:
/// sem absoluto, `..`, barra invertida nem nome vazio.
bool _hasBadPath(String name) {
  return name.isEmpty ||
      name.contains(r'\') ||
      name.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(name) ||
      name.split('/').contains('..');
}

/// Modo unix com tipo link simbólico (S_IFLNK), independente do que o
/// decodificador sinaliza: zips reais variam nesse ponto.
bool _isSymlinkMode(int mode) => ((mode >> 12) & 0xF) == 0xA;

/// Marca de Kodi: `addon.xml` na raiz, em qualquer das duas formas de
/// raiz aceitas. Vem antes de qualquer outra regra: um pacote do Kodi
/// costuma ter muitas entradas e merece a mensagem própria.
bool _isKodiPackage(List<ArchiveFile> files) {
  final names = files.map((f) => f.name).toList();
  if (names.contains('addon.xml')) return true;
  final firsts = names.map((n) => n.split('/').first).toSet();
  return firsts.length == 1 &&
      firsts.single.isNotEmpty &&
      names.contains('${firsts.single}/addon.xml');
}

/// Soma dos bytes reais extraídos, nunca o tamanho declarado no
/// cabeçalho (um zip bomb mente no cabeçalho). Descompacta sem guardar
/// e para ao passar de [limit]: 10 MB de zip podem virar 10 GB, que não
/// caberiam na memória para só então comparar. Pública para teste
/// direto, como [indexPackageFiles].
int extractedBytesTotal(
  List<ArchiveFile> files, {
  int limit = AddonPackageLimits.maxUncompressedBytes,
}) {
  final counter = _ByteCounter(limit);
  for (final file in files) {
    try {
      file.decompress(counter);
    } catch (_) {
      if (counter.exceeded) return counter.length;
      throw const AddonError.invalidManifest(
        'O pacote está corrompido ou não é um zip válido.',
      );
    }
    if (counter.exceeded) return counter.length;
  }
  return counter.length;
}

/// Saída que só conta os bytes e interrompe ao passar do limite.
class _ByteCounter extends OutputStream {
  _ByteCounter(this.limit) : super(byteOrder: ByteOrder.littleEndian);

  final int limit;
  bool exceeded = false;
  int _count = 0;

  void _add(int bytes) {
    _count += bytes;
    if (_count > limit) {
      exceeded = true;
      throw const _LimitReached();
    }
  }

  @override
  int get length => _count;

  @override
  void clear() => _count = 0;

  @override
  void flush() {}

  @override
  void writeByte(int value) => _add(1);

  @override
  void writeBytes(List<int> bytes, {int? length}) =>
      _add(length ?? bytes.length);

  @override
  void writeStream(InputStream stream) => _add(stream.length);

  // O inflate copia trechos anteriores por aqui: basta contar o tamanho.
  @override
  void writeBackReference(int distance, int count) => _add(count);

  @override
  Uint8List subset(int start, [int? end]) => Uint8List(0);
}

class _LimitReached implements Exception {
  const _LimitReached();
}

/// Índice base → arquivo da lista fechada (`baseNames` já normalizados,
/// na mesma ordem de `files`). Recusa duplicata, zip dentro de zip e
/// qualquer nome fora da lista; sem manifesto. Pública para teste
/// direto e reuso pelo fluxo de repositório (T4).
Map<String, ArchiveFile> indexPackageFiles(
    List<ArchiveFile> files, List<String> baseNames) {
  final byName = <String, ArchiveFile>{};
  for (var i = 0; i < files.length; i++) {
    final base = baseNames[i];
    if (byName.containsKey(base)) {
      throw AddonError.invalidManifest(
        'O pacote tem o arquivo duplicado: "$base".',
      );
    }
    if (base.toLowerCase().endsWith('.zip')) {
      throw const AddonError.invalidManifest(
        'O pacote tem zip dentro de zip, que o Olympus não abre.',
      );
    }
    if (base != 'addon.json' &&
        base != 'catalog.json' &&
        base != 'icon.png' &&
        base != 'fanart.jpg') {
      throw AddonError.invalidManifest(
        'O pacote tem um arquivo não aceito: "$base".',
      );
    }
    byName[base] = files[i];
  }
  if (!byName.containsKey('addon.json')) {
    throw const AddonError.invalidManifest(
      'O pacote não tem addon.json.',
    );
  }
  return byName;
}

/// Normaliza a raiz: arquivos soltos ficam como estão; se todos estão
/// sob uma única pasta, o prefixo sai. Qualquer outra mistura recusa
/// (devolve null). Diretórios não chegam aqui (só arquivos).
List<String>? _stripSingleRoot(List<String> names) {
  final parts = names.map((n) => n.split('/')).toList();
  if (parts.every((p) => p.length == 1)) return names;
  final firsts = parts.map((p) => p.first).toSet();
  if (firsts.length == 1 &&
      firsts.single.isNotEmpty &&
      parts.every((p) => p.length == 2)) {
    return parts.map((p) => p.last).toList();
  }
  return null;
}

/// Conteúdo real da entrada. Falha do decodificador vira recusa
/// controlada, nunca exceção crua para a UI.
Uint8List _contentOf(ArchiveFile file) {
  try {
    return Uint8List.fromList(file.content);
  } catch (_) {
    throw const AddonError.invalidManifest(
      'O pacote está corrompido ou não é um zip válido.',
    );
  }
}

/// Texto de uma entrada de texto (manifesto, catálogo): conteúdo
/// real, teto de 256 KB e UTF-8 válido, com as mensagens do chamador.
String _readTextEntry(
  ArchiveFile file, {
  required String tooBigMessage,
  required String invalidMessage,
}) {
  final bytes = _contentOf(file);
  if (bytes.length > AppConstants.maxManifestBytes) {
    throw AddonError.invalidManifest(tooBigMessage);
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    throw AddonError.invalidManifest(invalidMessage);
  }
}

AddonManifest _readManifest(ArchiveFile file) {
  return AddonManifest.parseJson(_readTextEntry(
    file,
    tooBigMessage: 'O manifesto é grande demais (limite de 256 KB).',
    invalidMessage: 'O pacote tem manifesto inválido.',
  ));
}

/// Devolve (texto, contagem, amostra). Catálogo vazio ou só com
/// inválidos recusa: pacote sem catálogo útil nunca cai no catálogo
/// de demonstração.
(String, int, List<String>) _readCatalog(ArchiveFile file) {
  final raw = _readTextEntry(
    file,
    tooBigMessage: 'O catálogo é grande demais (limite de 256 KB).',
    invalidMessage: 'O pacote tem catálogo inválido.',
  );
  final items = parseCatalogItems(raw);
  if (items.isEmpty) {
    throw const AddonError.invalidManifest(
      'O catálogo do pacote está vazio.',
    );
  }
  return (
    raw,
    items.length,
    items.take(5).map((item) => item.title).toList()
  );
}

Uint8List? _readImage(ArchiveFile? file, String label, int maxBytes) {
  if (file == null) return null;
  final bytes = _contentOf(file);
  if (bytes.length > maxBytes) {
    final mb = maxBytes ~/ (1024 * 1024);
    throw AddonError.invalidManifest(
      '$label é grande demais (limite de $mb MB).',
    );
  }
  if (!_isPng(bytes) && !_isJpeg(bytes)) {
    throw AddonError.invalidManifest(
      '$label não é um PNG nem um JPEG válido.',
    );
  }
  return bytes;
}

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

/// Varre os cabeçalhos locais do zip procurando o bit de
/// criptografia. Só vale o passeio limpo até o fim: se a estrutura
/// deraila, não há evidência (o decodificador decide, falhando
/// fechado do mesmo jeito).
bool _hasEncryptedEntry(Uint8List bytes) {
  var i = 0;
  var clean = true;
  while (i + 30 <= bytes.length) {
    if (!(bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x03 &&
        bytes[i + 3] == 0x04)) {
      i++;
      clean = false;
      continue;
    }
    final flags = bytes[i + 8] | (bytes[i + 9] << 8);
    if ((flags & 0x01) != 0 && clean) return true;
    final nameLength = bytes[i + 26] | (bytes[i + 27] << 8);
    final extraLength = bytes[i + 28] | (bytes[i + 29] << 8);
    final compressedSize = bytes[i + 18] |
        (bytes[i + 19] << 8) |
        (bytes[i + 20] << 16) |
        (bytes[i + 21] << 24);
    final next = i + 30 + nameLength + extraLength + compressedSize;
    if (next <= i || next > bytes.length) {
      clean = false;
      break;
    }
    i = next;
  }
  return false;
}
