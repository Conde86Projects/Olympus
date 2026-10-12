import 'package:flutter/widgets.dart';
import 'package:player/core/constants/app_constants.dart';

/// Modo TV herdado (Fase 4): a raiz publica a pref e os widgets
/// perguntam. Fora do [TvMode], tudo se comporta como desktop.
class TvMode extends InheritedWidget {
  const TvMode({super.key, required this.enabled, required super.child});

  final bool enabled;

  /// true com modo TV ligado; false fora dele ou sem ancestral.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvMode>()?.enabled ??
      false;

  /// Alvo minimo: 64 na TV, 44 no desktop (spec 3.4).
  static double minTarget(BuildContext context) =>
      of(context) ? AppConstants.tvMinTouchTarget : AppConstants.minTouchTarget;

  @override
  bool updateShouldNotify(TvMode oldWidget) =>
      enabled != oldWidget.enabled;
}
