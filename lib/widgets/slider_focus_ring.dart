import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';

/// Anel de foco para sliders (F6, Fase 4b, spec 18).
///
/// O halo padrão do Slider é pequeno demais para TV (10-foot) e o
/// foco do slider não aparece nos dumps de acessibilidade: quem chega
/// nele pelo D-pad percebe "foco perdido" (as setas passam a ajustar
/// o valor). Este wrapper desenha um anel na cor de destaque enquanto
/// qualquer descendente tem o foco. Fora da travessia: só pinta, o
/// foco continua sendo do slider.
class SliderFocusRing extends StatefulWidget {
  const SliderFocusRing({super.key, required this.child, this.padding = 4});

  final Widget child;

  /// Respiro fixo ao redor do slider (com e sem anel). A barra TV usa
  /// 2 para caber na altura compacta; o padrao 4 segue no desktop.
  final double padding;

  @override
  State<SliderFocusRing> createState() => _SliderFocusRingState();
}

class _SliderFocusRingState extends State<SliderFocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
    // Depois do frame: montado no meio de uma troca de layout (card de
    // janela baixa <-> normal), o foco ainda aponta para um elemento
    // sendo desativado, e subir os ancestrais dele dispara assert.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    var inside = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      if (e == context) {
        inside = true;
        return false;
      }
      return true;
    });
    if (inside != _focused) setState(() => _focused = inside);
  }

  @override
  Widget build(BuildContext context) {
    // Espessura do token na TV (spec 27.7); 3 no desktop, sem mudanca.
    final ringWidth = TvLayout.isTv(context)
        ? TvLayout.tokensOf(context).focusRingWidth
        : 3.0;
    return Container(
      // Padding fixo (com e sem anel) para o layout não pular.
      padding: EdgeInsets.all(widget.padding),
      // Decoracao SEMPRE presente (borda transparente sem foco): alternar
      // entre null e BoxDecoration remontaria o filho e destruiria o
      // FocusNode do slider a cada mudanca de foco.
      decoration: BoxDecoration(
        border: _focused
            ? Border.all(color: PlayerTheme.accent, width: ringWidth)
            : Border.all(color: Colors.transparent, width: ringWidth),
        borderRadius: BorderRadius.circular(10),
      ),
      child: widget.child,
    );
  }
}
