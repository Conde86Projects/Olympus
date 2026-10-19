import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';

/// Envolve uma linha com interruptor e aplica o desenho padrão do app
/// ([PlayerTheme.appSwitch]): trilho fino e cores neutras, igual na TV,
/// no desktop e no celular (padrão visual único, ver
/// `docs/PADROES_VISUAIS.md`).
class AppSwitchTheme extends StatelessWidget {
  const AppSwitchTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PlayerTheme.appSwitch(Theme.of(context)),
      child: child,
    );
  }
}
