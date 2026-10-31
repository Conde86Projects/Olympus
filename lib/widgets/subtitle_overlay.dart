import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player/core/utils/subtitle_style.dart';

/// Estilo escolhido em Ajustes e altura da barra de controles sobre o video,
/// para a legenda desenhada dentro do servico de player.
class SubtitleScope extends InheritedWidget {
  const SubtitleScope({
    super.key,
    required this.style,
    required this.bottomInset,
    required super.child,
  });

  final SubtitleStyle style;
  final ValueListenable<double> bottomInset;

  static SubtitleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubtitleScope>();

  @override
  bool updateShouldNotify(SubtitleScope oldWidget) =>
      style != oldWidget.style || bottomInset != oldWidget.bottomInset;
}

/// Linhas da legenda sobre a area do video, no [SubtitleStyle]. So pinta:
/// toques e foco continuam com o que esta embaixo.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({super.key, required this.lines, this.style});

  /// Espaco entre a legenda e a barra de controles visivel.
  static const barGap = 8.0;

  final List<String> lines;

  /// Sem valor, usa o de [SubtitleScope] ou o padrao.
  final SubtitleStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ].join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    final scope = SubtitleScope.maybeOf(context);
    final resolved = style ?? scope?.style ?? SubtitleStyle.defaults;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final label = Text(
            text,
            textAlign: TextAlign.center,
            // A proporcao ja vem da area: sem escala do sistema por cima.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              height: 1.4,
              fontSize: resolved.fontSizeFor(area),
              color: resolved.textColor,
              backgroundColor: resolved.backgroundColor,
            ),
          );
          return ValueListenableBuilder<double>(
            valueListenable:
                scope?.bottomInset ?? const AlwaysStoppedAnimation<double>(0),
            child: label,
            builder: (context, inset, child) => AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                max(resolved.bottomFor(area), inset > 0 ? inset + barGap : 0),
              ),
              child: Align(alignment: Alignment.bottomCenter, child: child),
            ),
          );
        },
      ),
    );
  }
}
