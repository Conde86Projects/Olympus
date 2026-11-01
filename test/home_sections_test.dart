import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/home/home_sections.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';

/// T7: fileiras do Início no desktop. Modelo puro: entradas +
/// biblioteca viram seções; a tela só apresenta.
MediaItem item(
  String id, {
  MediaSourceType type = MediaSourceType.url,
  bool favorite = false,
  DateTime? addedAt,
  DateTime? lastPlayedAt,
  Duration? duration,
}) =>
    MediaItem(
      id: id,
      title: 'Título $id',
      sourceType: type,
      source: type == MediaSourceType.local
          ? '/videos/$id.mp4'
          : 'https://exemplo.com/$id.mp4',
      addedAt: addedAt ?? DateTime(2026, 1, 1),
      lastPlayedAt: lastPlayedAt,
      duration: duration,
      isFavorite: favorite,
    );

HistoryEntry entry(
  String id, {
  Duration? position,
  double? percent,
  bool completed = false,
}) =>
    HistoryEntry(
      mediaId: id,
      accessedAt: DateTime(2026, 1, 2),
      position: position,
      percentWatched: percent,
      completed: completed,
    );

void main() {
  group('homeSections', () {
    test('vazio não gera fileira', () {
      expect(homeSections(entries: const [], items: const []), isEmpty);
    });

    test('continuar assistindo carrega a posição salva', () {
      final sections = homeSections(
        entries: [entry('a', position: const Duration(minutes: 1))],
        items: [item('a', duration: const Duration(minutes: 10))],
      );
      expect(sections, hasLength(1));
      expect(sections.single.title, 'Continuar assistindo');
      expect(sections.single.items.map((i) => i.id), ['a']);
      expect(sections.single.items.single.lastPosition,
          const Duration(minutes: 1));
    });

    test('concluído, 100% e id desconhecido saem', () {
      final sections = homeSections(
        entries: [
          entry('a', completed: true),
          entry('b', percent: 1.0),
          entry('c', position: const Duration(minutes: 1)),
          entry('fantasma', position: const Duration(minutes: 1)),
        ],
        items: [
          item('a', duration: const Duration(minutes: 10)),
          item('b', duration: const Duration(minutes: 10)),
          item('c', duration: const Duration(minutes: 10)),
        ],
      );
      expect(sections, hasLength(1));
      expect(sections.single.items.map((i) => i.id), ['c']);
    });

    test('duplicado no histórico conta uma vez', () {
      final sections = homeSections(
        entries: [
          entry('a', position: const Duration(minutes: 1)),
          entry('a', position: const Duration(minutes: 2)),
        ],
        items: [item('a', duration: const Duration(minutes: 10))],
      );
      expect(sections.single.items, hasLength(1));
      expect(sections.single.items.single.lastPosition,
          const Duration(minutes: 1));
    });

    test('resumível vem antes; desempate pela recência', () {
      final sections = homeSections(
        entries: [
          entry('velho'),
          entry('novo', position: const Duration(seconds: 10)),
          entry('recente'),
        ],
        items: [
          item('velho',
              duration: const Duration(minutes: 10),
              addedAt: DateTime(2026, 1, 1)),
          item('novo',
              duration: const Duration(minutes: 10),
              addedAt: DateTime(2026, 1, 1)),
          item('recente',
              duration: const Duration(minutes: 10),
              addedAt: DateTime(2026, 1, 3)),
        ],
      );
      expect(
          sections.single.items.map((i) => i.id), ['novo', 'recente', 'velho']);
    });

    test('continuar assistindo respeita o limite', () {
      final entries = [
        for (var i = 0; i < 12; i++)
          entry('v$i', position: const Duration(seconds: 10)),
      ];
      final items = [
        for (var i = 0; i < 12; i++)
          item('v$i', duration: const Duration(minutes: 10)),
      ];
      final sections = homeSections(entries: entries, items: items);
      expect(sections.single.items, hasLength(10));
    });

    test('arquivos locais por recência de adição', () {
      final sections = homeSections(
        entries: const [],
        items: [
          item('link', type: MediaSourceType.url),
          item('velho',
              type: MediaSourceType.local, addedAt: DateTime(2026, 1, 1)),
          item('novo',
              type: MediaSourceType.local, addedAt: DateTime(2026, 1, 5)),
        ],
      );
      expect(sections, hasLength(1));
      expect(sections.single.title, 'Arquivos locais');
      expect(
          sections.single.items.map((i) => i.id), ['novo', 'velho']);
    });

    test('favoritos na ordem da biblioteca', () {
      final sections = homeSections(
        entries: const [],
        items: [
          item('a', favorite: true),
          item('b'),
          item('c', favorite: true),
        ],
      );
      expect(sections, hasLength(1));
      expect(sections.single.title, 'Favoritos');
      expect(sections.single.items.map((i) => i.id), ['a', 'c']);
    });

    test('ordem das fileiras e vazias somem', () {
      final sections = homeSections(
        entries: const [],
        items: [
          item('f', type: MediaSourceType.url, favorite: true),
          item('l', type: MediaSourceType.local),
        ],
      );
      expect(
          sections.map((s) => s.title), ['Arquivos locais', 'Favoritos']);
    });

    test('item nas três aparece nas três', () {
      final sections = homeSections(
        entries: [entry('a', position: const Duration(seconds: 5))],
        items: [
          item('a',
              type: MediaSourceType.local,
              favorite: true,
              duration: const Duration(minutes: 10)),
        ],
      );
      expect(sections, hasLength(3));
      for (final section in sections) {
        expect(section.items.map((i) => i.id), ['a']);
      }
    });
  });
}
