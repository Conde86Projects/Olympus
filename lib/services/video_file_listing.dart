import 'dart:io';

/// Extensões de vídeo aceitas pelo navegador de arquivos da TV.
const videoExtensions = {
  '.mp4',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.m4v',
  '.ts'
};

/// Pastas padrão onde a TV procura vídeos (Android).
const tvBrowseRoots = [
  '/sdcard/Download',
  '/sdcard/Movies',
  '/sdcard/DCIM',
];

/// Um item do navegador: pasta ou vídeo.
class BrowserEntry {
  const BrowserEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

/// Só vídeos pela extensão (sem diferenciar maiúsculas).
bool isVideoFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return videoExtensions.contains(name.substring(dot).toLowerCase());
}

/// Conteúdo visível de uma pasta: subpastas primeiro, depois vídeos, em
/// ordem alfabética. Ocultos (começam com ".") ficam fora. Pasta
/// inexistente ou sem leitura devolve lista vazia em vez de falhar.
Future<List<BrowserEntry>> listVideoFolder(String dirPath) async {
  final dir = Directory(dirPath);
  final folders = <BrowserEntry>[];
  final videos = <BrowserEntry>[];
  try {
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        folders.add(
            BrowserEntry(name: name, path: entity.path, isDirectory: true));
      } else if (entity is File && isVideoFileName(name)) {
        videos.add(
            BrowserEntry(name: name, path: entity.path, isDirectory: false));
      }
    }
  } on FileSystemException {
    return const [];
  }
  int byName(BrowserEntry a, BrowserEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  folders.sort(byName);
  videos.sort(byName);
  return [...folders, ...videos];
}
