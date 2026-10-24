import 'package:flutter/foundation.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/addon_catalog_item.dart';

/// Opcoes da fonte (5C): selecao viva da rendicao. Objeto imutavel de
/// configuracao pura (so dados, sem comportamento). Null = feature
/// ausente. Quando presente, a troca e obrigatoria (regra que era um
/// comentario de doc no painel).
class SourceOptions {
  const SourceOptions({
    required this.qualities,
    this.selectedId,
    this.selectedListenable,
    required this.onSelect,
  });

  /// Rendicoes informadas pela fonte. Vazia = sem secao (como antes).
  final List<SourceQuality> qualities;

  /// Rendicao atual (null = URL padrao da midia).
  final String? selectedId;

  /// Ouvinte ao vivo da selecao: quando presente, o valor dele vale
  /// sobre [selectedId] sem precisar reabrir o painel.
  final ValueListenable<String?>? selectedListenable;

  /// Selecao resolvida (ouvinte ao vivo vale sobre o instantaneo).
  String? get resolvedId => selectedListenable?.value ?? selectedId;

  /// Troca de rendicao (null volta ao padrao).
  final Future<void> Function(String? qualityId) onSelect;
}

/// Opcoes do seletor HLS: selecao viva da qualidade. Objeto imutavel
/// de configuracao pura (so dados, sem comportamento). Null = feature
/// ausente.
class HlsOptions {
  const HlsOptions({
    required this.qualities,
    this.selectedId,
    this.selectedListenable,
    required this.onSelect,
    this.effectiveLabel,
    this.effectiveListenable,
  });

  /// Opcoes do seletor (Automatica/Original/variantes reais).
  final List<HlsQualityOption> qualities;

  /// Selecao atual (id da opcao; padrao Automatica).
  final String? selectedId;

  /// Ouvinte ao vivo da selecao (dialogo e rota separada). Quando
  /// presente, o valor dele vale sobre [selectedId].
  final ValueListenable<String>? selectedListenable;

  /// Selecao resolvida (ouvinte ao vivo vale sobre o instantaneo).
  String? get resolvedId => selectedListenable?.value ?? selectedId;

  /// Troca de qualidade HLS pelo id da opcao.
  final Future<void> Function(String qualityId) onSelect;

  /// Qualidade efetivamente aberta na Automatica (ex. "288p").
  /// Null = master/Original.
  final String? effectiveLabel;

  /// Ouvinte ao vivo da qualidade efetiva.
  final ValueListenable<String?>? effectiveListenable;

  /// Rotulo efetivo resolvido (ouvinte ao vivo vale sobre o instantaneo).
  String? get resolvedEffectiveLabel =>
      effectiveListenable?.value ?? effectiveLabel;
}
