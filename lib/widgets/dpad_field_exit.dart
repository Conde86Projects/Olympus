import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Saída de campo de texto por D-pad (F4, Fase 4b, spec 18).
///
/// O TextField consome as setas verticais (cursor) e o remoto não tem
/// TAB: sem isto, o foco entra no campo e não sai mais. UP/DOWN aqui
/// devolvem o foco à travessia direcional; LEFT/RIGHT continuam com o
/// campo (movem o cursor). Em campo multilinha, a seta só sai na
/// primeira/última linha — dentro do texto, ela move o cursor.
class DpadFieldExit extends StatelessWidget {
  const DpadFieldExit({
    super.key,
    required this.controller,
    required this.child,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Fora da travessia: este nó é só interceptador de tecla, nunca
      // parada de foco (as teclas borbulham até ele de qualquer forma).
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final dir = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          LogicalKeyboardKey.arrowDown => TraversalDirection.down,
          _ => null,
        };
        if (dir == null) return KeyEventResult.ignored;
        if (!_atVerticalEdge(dir)) return KeyEventResult.ignored;
        return node.focusInDirection(dir)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: child,
    );
  }

  bool _atVerticalEdge(TraversalDirection dir) {
    final text = controller.text;
    if (!text.contains('\n')) return true;
    final offset = controller.selection.baseOffset.clamp(0, text.length);
    if (dir == TraversalDirection.up) {
      return !text.substring(0, offset).contains('\n');
    }
    return !text.substring(offset).contains('\n');
  }
}
