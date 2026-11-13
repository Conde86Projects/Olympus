import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/widgets/dpad_field_exit.dart';

/// Campo de texto para o controle remoto da TV.
///
/// Sem isto, o foco só entra no campo pelo miolo do texto (que é estreito) e
/// a seta para baixo passa direto por ele; além disso o teclado da TV abre no
/// instante em que o foco chega, cobrindo a tela de quem só estava passando.
/// Aqui a moldura inteira é a parada do foco, e o teclado só abre com OK. Fora
/// da TV vale só a saída por setas de [DpadFieldExit].
///
/// [fieldFocus] é o nó do `TextField` filho: ele deixa de ser parada da
/// travessia (a moldura é a parada) e segue podendo receber foco por código.
class TvTextFieldFrame extends StatefulWidget {
  const TvTextFieldFrame({
    super.key,
    required this.controller,
    required this.fieldFocus,
    required this.child,
  });

  final TextEditingController controller;
  final FocusNode fieldFocus;
  final Widget child;

  @override
  State<TvTextFieldFrame> createState() => _TvTextFieldFrameState();
}

class _TvTextFieldFrameState extends State<TvTextFieldFrame> {
  final _frame = FocusNode(debugLabel: 'TvTextFieldFrame');

  static final _openKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = DpadFieldExit(
      controller: widget.controller,
      child: widget.child,
    );
    if (!TvLayout.isTv(context)) return field;
    widget.fieldFocus.skipTraversal = true;
    return Focus(
      focusNode: _frame,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _openKeys.contains(event.logicalKey)) {
          widget.fieldFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _frame,
        builder: (context, child) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: _frame.hasPrimaryFocus
                ? Border.all(color: PlayerTheme.accent, width: 3)
                : null,
          ),
          child: child,
        ),
        child: field,
      ),
    );
  }
}
