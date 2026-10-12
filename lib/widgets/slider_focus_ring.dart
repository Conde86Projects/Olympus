import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';

/// Anel de foco para sliders (F6, Fase 4b, spec 18).
///
/// O halo padrão do Slider é pequeno demais para TV (10-foot) e o
/// foco do slider não aparece nos dumps de acessibilidade: quem chega
/// nele pelo D-pad percebe "foco perdido" (as setas passam a ajustar
/// o valor). Este wrapper desenha um anel na cor de destaque enquanto
/// qualquer descendente tem o foco. Fora da travessia: só pinta, o
/// foco continua sendo do slider.
class SliderFocusRing extends StatefulWidget {
  const SliderFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<SliderFocusRing> createState() => _SliderFocusRingState();
}

class _SliderFocusRingState extends State<SliderFocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
    _sync();
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
    return Container(
      // Padding fixo (com e sem anel) para o layout não pular.
      padding: const EdgeInsets.all(4),
      // Decoracao SEMPRE presente (borda transparente sem foco): alternar
      // entre null e BoxDecoration remontaria o filho e destruiria o
      // FocusNode do slider a cada mudanca de foco.
      decoration: BoxDecoration(
        border: _focused
            ? Border.all(color: PlayerTheme.accent, width: 3)
            : Border.all(color: Colors.transparent, width: 3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: widget.child,
    );
  }
}
