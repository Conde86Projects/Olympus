import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/widgets/player_panel_options.dart';

/// Contrato dos clusters do painel (Q1b/Q2a/Q3a): fonte 5C e HLS como
/// objetos imutaveis de configuracao pura; null = feature ausente.
void main() {
  group('opcoes do painel (config pura)', () {
    test('ausencia e null; presente exige troca', () {
      const SourceOptions? absent = null;
      expect(absent, isNull);

      final present = SourceOptions(
        qualities: const [
          SourceQuality(id: 'q720', label: '720p', sourceUrl: 'https://exemplo.com/720.mp4'),
        ],
        selectedId: 'q720',
        onSelect: (_) async {},
      );
      expect(present.qualities, hasLength(1));
      expect(present.selectedId, 'q720');
      expect(present.selectedListenable, isNull);
    });

    test('hls carrega o rotulo efetivo e o ouvinte', () {
      final options = HlsOptions(
        qualities: const [
          HlsQualityOption(id: 'auto', label: 'Automatica'),
        ],
        selectedId: 'auto',
        selectedListenable: ValueNotifier<String>('auto'),
        onSelect: (_) async {},
        effectiveLabel: '288p',
        effectiveListenable: ValueNotifier<String?>('288p'),
      );
      expect(options.qualities, hasLength(1));
      expect(options.effectiveLabel, '288p');
      expect(options.effectiveListenable?.value, '288p');
    });
  });
}
