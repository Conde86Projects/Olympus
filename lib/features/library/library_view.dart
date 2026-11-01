import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';

/// Texto sem maiúsculas e sem acentos, para comparar títulos e buscas.
String foldForSearch(String text) {
  const accented = 'áàâãäåéèêëíìîïóòôõöúùûüçñ';
  const plain = 'aaaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final at = accented.indexOf(char);
    out.write(at < 0 ? char : plain[at]);
  }
  return out.toString();
}

/// Itens da Biblioteca como a tela os mostra: só os que casam com a busca,
/// na ordem pedida. Busca com várias palavras exige todas no título.
/// Empate de ordem desempata pelos adicionados mais recentemente.
List<MediaItem> libraryView(
  List<MediaItem> items, {
  String query = '',
  LibrarySort sort = LibrarySort.recent,
}) {
  final words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final found = [
    for (final item in items)
      if (words.isEmpty || _matchesAll(foldForSearch(item.title), words)) item,
  ];
  int newestFirst(MediaItem a, MediaItem b) => b.addedAt.compareTo(a.addedAt);
  int byTitle(MediaItem a, MediaItem b) =>
      foldForSearch(a.title).compareTo(foldForSearch(b.title));
  int longestFirst(MediaItem a, MediaItem b) {
    final x = a.duration, y = b.duration;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }

  final primary = switch (sort) {
    LibrarySort.recent => newestFirst,
    LibrarySort.title => byTitle,
    LibrarySort.duration => longestFirst,
  };
  found.sort((a, b) {
    final result = primary(a, b);
    return result != 0 ? result : newestFirst(a, b);
  });
  return found;
}

bool _matchesAll(String title, List<String> words) =>
    words.every(title.contains);
