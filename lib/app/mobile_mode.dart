import 'package:flutter/widgets.dart';

/// Composicao de celular (toque): Android/iOS com o modo TV desligado.
/// A raiz publica e os widgets perguntam, como no [TvMode]. Fora do
/// [MobileMode] (desktop, TV, testes), tudo segue como antes: nada de
/// navegacao inferior, alvos de 44 e o player de desktop.
class MobileMode extends InheritedWidget {
  const MobileMode({super.key, required this.enabled, required super.child});

  final bool enabled;

  /// Alvo minimo de toque no celular (Material: 48 dp).
  static const minTouchTarget = 48.0;

  /// true no celular; false fora dele ou sem ancestral.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileMode>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(MobileMode oldWidget) =>
      enabled != oldWidget.enabled;
}
