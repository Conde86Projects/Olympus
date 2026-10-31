import 'package:flutter/material.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/preferences_service.dart';

/// Linhas da aparencia da legenda em Ajustes: tamanho, cor, posicao e fundo.
List<Widget> subtitleAppearanceRows(PreferencesService prefs) {
  final current = prefs.current;
  return [
    _Choice<SubtitleSize>(
      title: 'Tamanho',
      value: current.subtitleSize,
      labels: const {
        SubtitleSize.small: 'Pequeno',
        SubtitleSize.medium: 'Médio',
        SubtitleSize.large: 'Grande',
      },
      onChanged: (v) => prefs.update(current.copyWith(subtitleSize: v)),
    ),
    _Choice<SubtitleColor>(
      title: 'Cor',
      value: current.subtitleColor,
      labels: const {
        SubtitleColor.white: 'Branca',
        SubtitleColor.yellow: 'Amarela',
        SubtitleColor.cyan: 'Ciano',
      },
      onChanged: (v) => prefs.update(current.copyWith(subtitleColor: v)),
    ),
    _Choice<SubtitlePosition>(
      title: 'Posição',
      value: current.subtitlePosition,
      labels: const {
        SubtitlePosition.low: 'Baixa',
        SubtitlePosition.normal: 'Normal',
        SubtitlePosition.high: 'Alta',
      },
      onChanged: (v) => prefs.update(current.copyWith(subtitlePosition: v)),
    ),
    SwitchListTile(
      title: const Text('Fundo atrás do texto'),
      value: current.subtitleBackground,
      onChanged: (v) => prefs.update(current.copyWith(subtitleBackground: v)),
    ),
  ];
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
