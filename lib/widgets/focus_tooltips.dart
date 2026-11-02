import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mostra o balão do controle quando a seleção chega nele pelo teclado ou
/// pelo controle remoto. O [Tooltip] do Flutter só reage a mouse e a toque
/// longo, então na TV nenhum ícone dizia o que era. Vale para todo tooltip
/// do app, sem mexer em quem o usa.
///
/// Só reage a tecla: foco dado pelo app ao abrir uma tela ou por um clique
/// não mostra balão. Desligado no celular, onde a barra inferior tem nomes.
class FocusTooltips extends StatefulWidget {
  const FocusTooltips({super.key, required this.enabled, required this.child});

  static const showFor = Duration(seconds: 4);

  final bool enabled;
  final Widget child;

  @override
  State<FocusTooltips> createState() => _FocusTooltipsState();
}

class _FocusTooltipsState extends State<FocusTooltips> {
  FocusNode? _lastFocus;
  Timer? _hide;
  bool _showing = false;

  /// A última interação foi tecla (e não ponteiro).
  bool _keyDriven = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    _hide?.cancel();
    FocusManager.instance.removeListener(_onFocusChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _keyDriven = true;
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _keyDriven = false;
  }

  void _onFocusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _lastFocus)) return;
    _lastFocus = node;
    _dismiss();
    if (!widget.enabled || !_keyDriven) return;
    final tooltip = node?.context?.findAncestorStateOfType<TooltipState>();
    if (tooltip == null) return;
    tooltip.ensureTooltipVisible();
    _showing = true;
    _hide = Timer(FocusTooltips.showFor, _dismiss);
  }

  void _dismiss() {
    _hide?.cancel();
    _hide = null;
    if (!_showing) return;
    _showing = false;
    Tooltip.dismissAllToolTips();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
