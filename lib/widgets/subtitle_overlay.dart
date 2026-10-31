import 'package:flutter/material.dart';
import 'package:player/core/utils/subtitle_style.dart';

/// Linhas da legenda sobre a area do video, no [SubtitleStyle]. So pinta:
/// toques e foco continuam com o que esta embaixo.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.lines,
    this.style = SubtitleStyle.defaults,
  });

  final List<String> lines;
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final text = [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ].join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, style.bottomFor(area)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                text,
                textAlign: TextAlign.center,
                // A proporcao ja vem da area: sem escala do sistema por cima.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  height: 1.4,
                  fontSize: style.fontSizeFor(area),
                  color: style.textColor,
                  backgroundColor: style.backgroundColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
