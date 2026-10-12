import 'package:flutter/material.dart';

/// Saida de teclado/D-pad do slider (Fase 4): o Slider consome as
/// quatro setas para ajustar, e sem isso quem foca nele nao sai mais.
/// Com foco aqui, Enter ou OK movem para [exit]. Sobrescreve o
/// [ActivateIntent] (e nao um atalho): o Slider interno consome o OK
/// antes de qualquer [Shortcuts] ao redor, mas a ativacao passa por
/// aqui. O OK (select) e obrigatorio: no controle remoto o DPAD_CENTER
/// chega como select, nao como enter.
class ExitSlider extends StatelessWidget {
  const ExitSlider({super.key, required this.exit, required this.child});

  final TraversalDirection exit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            FocusScope.of(context).focusInDirection(exit);
            return null;
          },
        ),
      },
      child: child,
    );
  }
}
