import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/media_player_service.dart';

MediaItem _item({Duration? position, Duration? duration}) => MediaItem(
      id: '1',
      title: 'Exemplo',
      sourceType: MediaSourceType.local,
      source: r'C:\videos\exemplo.mp4',
      duration: duration,
      lastPosition: position,
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('MediaItem', () {
    test('progress retorna fracao assistida', () {
      final item = _item(
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 10),
      );
      expect(item.progress, 0.5);
    });

    test('progress e null sem duracao ou posicao', () {
      expect(_item().progress, isNull);
      expect(_item(duration: const Duration(minutes: 10)).progress, isNull);
    });

    test('isResumable exige posicao e descarta fim proximo', () {
      expect(_item().isResumable, isFalse);
      expect(
          _item(
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 10),
          ).isResumable,
          isTrue);
      expect(
          _item(
            position: const Duration(minutes: 10) - const Duration(seconds: 2),
            duration: const Duration(minutes: 10),
          ).isResumable,
          isFalse);
    });

    test('toMap/fromMap preservam os campos', () {
      final item = _item(
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 2),
      ).copyWith(isFavorite: true);
      final roundTrip = MediaItem.fromMap(item.toMap());
      expect(roundTrip.id, item.id);
      expect(roundTrip.title, item.title);
      expect(roundTrip.source, item.source);
      expect(roundTrip.duration, item.duration);
      expect(roundTrip.lastPosition, item.lastPosition);
      expect(roundTrip.isFavorite, isTrue);
    });
  });

  group('HistoryEntry', () {
    test('toMap/fromMap preservam os campos', () {
      final entry = HistoryEntry(
        mediaId: '1',
        accessedAt: DateTime(2026, 2, 2, 12),
        position: const Duration(seconds: 90),
        percentWatched: 0.75,
        completed: false,
      );
      final roundTrip = HistoryEntry.fromMap(entry.toMap());
      expect(roundTrip.mediaId, '1');
      expect(roundTrip.position, const Duration(seconds: 90));
      expect(roundTrip.percentWatched, 0.75);
      expect(roundTrip.completed, isFalse);
    });
  });

  group('UserPreferences', () {
    test('padroes seguem a spec', () {
      const prefs = UserPreferences();
      expect(prefs.theme, AppThemeMode.dark);
      expect(prefs.rememberPosition, isTrue);
      expect(prefs.language, 'pt-BR');
    });

    test('fromMap tolera mapa parcial', () {
      final prefs = UserPreferences.fromMap({'theme': 'system'});
      expect(prefs.theme, AppThemeMode.system);
      expect(prefs.rememberPosition, isTrue);
    });

    test('geometria da janela sobrevive a serializacao', () {
      const prefs = UserPreferences();
      expect(prefs.windowWidth, isNull);
      final withBounds = prefs.copyWith(
        windowX: () => 120,
        windowY: () => 80,
        windowWidth: () => 1600,
        windowHeight: () => 900,
      );
      final roundTrip = UserPreferences.fromMap(withBounds.toMap());
      expect(roundTrip.windowX, 120);
      expect(roundTrip.windowY, 80);
      expect(roundTrip.windowWidth, 1600);
      expect(roundTrip.windowHeight, 900);
    });
  });

  group('rotation', () {
    test('NoOp normaliza quartos de volta em 0-3', () async {
      const player = NoOpMediaPlayerService();
      final start = player.session.rotation;
      await player.rotateClockwise();
      expect(player.session.rotation, (start + 1) % 4);
      await player.rotateCounterClockwise();
      expect(player.session.rotation, start);
      await player.rotateCounterClockwise();
      expect(player.session.rotation, (start + 3) % 4);
      // Restaura o estado estatico para os outros testes.
      await player.rotateClockwise();
      expect(player.session.rotation, start);
    });
  });

  group('media_utils', () {
    test('formatTimestamp formata minutos e horas', () {
      expect(formatTimestamp(const Duration(seconds: 754)), '12:34');
      expect(formatTimestamp(const Duration(seconds: 4354)), '1:12:34');
      expect(formatTimestamp(const Duration(seconds: -5)), '0:00');
    });

    test('titleFromSource extrai nome amigavel', () {
      expect(titleFromSource(r'C:\Videos\meu_filme-2.mp4'), 'meu filme 2');
      expect(titleFromSource('https://exemplo.com/aula%201.mp4?x=1'), 'aula 1');
    });

    test('isSupportedUrl aceita apenas http/https com host', () {
      expect(isSupportedUrl('https://exemplo.com/v.mp4'), isTrue);
      expect(isSupportedUrl('http://exemplo.com/v'), isTrue);
      expect(isSupportedUrl('ftp://exemplo.com/v'), isFalse);
      expect(isSupportedUrl('nao e url'), isFalse);
      expect(isSupportedUrl(''), isFalse);
    });
  });
}
