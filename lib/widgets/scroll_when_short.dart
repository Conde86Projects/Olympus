import 'package:flutter/widgets.dart';

/// Rola o [child] so quando a altura nao basta (janela baixa no
/// Windows, ex.: compacto 480x270). Com espaco de sobra a caixa minima
/// ocupa a area toda e um [Center] dentro do filho posiciona igual a
/// antes: o desenho em tamanhos normais nao muda.
class ScrollWhenShort extends StatelessWidget {
  const ScrollWhenShort({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
