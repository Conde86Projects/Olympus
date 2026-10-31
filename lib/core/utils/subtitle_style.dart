import 'dart:math';

import 'package:flutter/painting.dart';

/// Estilo das legendas (F6, U01). A legenda e desenhada pelo Flutter: com
/// `libass` desligado o media_kit desativa a do mpv (`sub-visibility=no`),
/// entao as propriedades `sub-*` nao tem efeito. Tamanho e posicao sao
/// proporcionais a area do video para valer em TV, celular e janela.
class SubtitleStyle {
  const SubtitleStyle({
    this.textColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0x80000000),
    this.bottomFraction = 0.10,
    this.sizeFraction = 0.045,
    this.minFontSize = 16,
    this.maxFontSize = 40,
  });

  /// Padrao do projeto: texto branco, fundo preto semitransparente,
  /// 10% acima da base da area do video.
  static const defaults = SubtitleStyle();

  final Color textColor;

  /// Fundo atras do texto; transparente para nao ter fundo.
  final Color backgroundColor;

  /// Distancia da base, como fracao da altura da area do video.
  final double bottomFraction;

  /// Tamanho da fonte, como fracao do menor lado da area do video.
  final double sizeFraction;

  final double minFontSize;
  final double maxFontSize;

  double fontSizeFor(Size area) =>
      (min(area.width, area.height) * sizeFraction)
          .clamp(minFontSize, maxFontSize);

  double bottomFor(Size area) => area.height * bottomFraction;
}
