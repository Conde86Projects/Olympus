import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_mode.dart';

/// Envolve uma linha com interruptor: na TV, o Switch fica no desenho
/// compacto e neutro de [PlayerTheme.tvSwitch]; fora da TV, nada muda.
/// O Theme fica sempre na arvore para alternar o modo TV sem remontar.
class TvSwitchTheme extends StatelessWidget {
  const TvSwitchTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: TvMode.of(context) ? PlayerTheme.tvSwitch(theme) : theme,
      child: child,
    );
  }
}
