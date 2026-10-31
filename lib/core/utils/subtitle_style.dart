import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:player/models/preferences.dart';

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

  /// Traduz as escolhas de Ajustes; o padrao delas equivale a [defaults].
  factory SubtitleStyle.fromPreferences(UserPreferences prefs) {
    final scale = switch (prefs.subtitleSize) {
      SubtitleSize.small => 0.8,
      SubtitleSize.medium => 1.0,
      SubtitleSize.large => 1.3,
    };
    return SubtitleStyle(
      textColor: switch (prefs.subtitleColor) {
        SubtitleColor.white => const Color(0xFFFFFFFF),
        SubtitleColor.yellow => const Color(0xFFFFEB3B),
        SubtitleColor.cyan => const Color(0xFF4DD0E1),
      },
      backgroundColor: prefs.subtitleBackground
          ? const Color(0x80000000)
          : const Color(0x00000000),
      bottomFraction: switch (prefs.subtitlePosition) {
        SubtitlePosition.low => 0.05,
        SubtitlePosition.normal => 0.10,
        SubtitlePosition.high => 0.20,
      },
      sizeFraction: 0.045 * scale,
      minFontSize: 16 * scale,
      maxFontSize: 40 * scale,
    );
  }

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
