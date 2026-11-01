import 'package:player/core/constants/app_constants.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';

/// Fileira da tela inicial no desktop (T7): título + itens.
class HomeSection {
  const HomeSection({required this.title, required this.items});

  final String title;
  final List<MediaItem> items;
}

/// Índice id → item para a regra do Continuar assistindo.
Map<String, MediaItem> itemsById(List<MediaItem> items) =>
    {for (final item in items) item.id: item};

/// Fileiras do Início, nessa ordem: Continuar assistindo, Arquivos
/// locais e Favoritos; vazias somem. Pura, para teste direto; a tela
/// só apresenta.
List<HomeSection> homeSections({
  required List<HistoryEntry> entries,
  required List<MediaItem> items,
}) {
  final byId = itemsById(items);
  final sections = <HomeSection>[];
  final resume = continueWatchingItems(entries: entries, byId: byId);
  if (resume.isNotEmpty) {
    sections.add(HomeSection(title: 'Continuar assistindo', items: resume));
  }
  final locals = [
    for (final item in items)
      if (item.sourceType == MediaSourceType.local) item,
  ]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  if (locals.isNotEmpty) {
    sections.add(HomeSection(title: 'Arquivos locais', items: locals));
  }
  final favorites = [
    for (final item in items)
      if (item.isFavorite) item,
  ];
  if (favorites.isNotEmpty) {
    sections.add(HomeSection(title: 'Favoritos', items: favorites));
  }
  return sections;
}

/// Regra do "Continuar assistindo" movida da [HomeScreen] sem mudar o
/// resultado (T7): junta histórico + biblioteca, tira concluído e
/// desconhecido, limita e ordena (resumível antes, recência depois).
List<MediaItem> continueWatchingItems({
  required List<HistoryEntry> entries,
  required Map<String, MediaItem> byId,
}) {
  final seen = <String>{};
  final result = <MediaItem>[];
  for (final entry in entries) {
    if (!seen.add(entry.mediaId)) continue;
    final item = byId[entry.mediaId];
    if (item == null ||
        entry.completed ||
        AppConstants.isCompletedPosition(percent: entry.percentWatched)) {
      continue;
    }
    result.add(item.copyWith(lastPosition: () => entry.position));
    if (result.length >= AppConstants.continueWatchingLimit) break;
  }
  result.sort((a, b) {
    final ra = a.isResumable ? 0 : 1;
    final rb = b.isResumable ? 0 : 1;
    if (ra != rb) return ra.compareTo(rb);
    return (b.lastPlayedAt ?? b.addedAt)
        .compareTo(a.lastPlayedAt ?? a.addedAt);
  });
  return result;
}
