import 'package:flutter/widgets.dart';

/// Modo TV herdado (Fase 4): a raiz publica a pref e os widgets
/// perguntam. Fora do [TvMode], tudo se comporta como desktop.
/// Metricas e alvos moram no TvLayout (spec 27.7).
class TvMode extends InheritedWidget {
  const TvMode({super.key, required this.enabled, required super.child});

  final bool enabled;

  /// true com modo TV ligado; false fora dele ou sem ancestral.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvMode>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(TvMode oldWidget) =>
      enabled != oldWidget.enabled;
}
