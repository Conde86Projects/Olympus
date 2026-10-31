import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Mede quanto a barra de controles cobre da base do video, para a legenda
/// subir enquanto a barra esta visivel. Quem usa so marca os dois widgets
/// com [areaKey] e [barKey] e pede [schedule] quando o layout pode mudar.
class SubtitleBarInset {
  SubtitleBarInset({required this.barVisible});

  /// Barra oculta conta como zero mesmo mantendo o tamanho no layout.
  final bool Function() barVisible;

  final areaKey = GlobalKey();
  final barKey = GlobalKey();

  final _inset = ValueNotifier<double>(0);
  bool _disposed = false;

  ValueListenable<double> get inset => _inset;

  /// Mede depois do proximo quadro, com o layout ja resolvido.
  void schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void dispose() {
    _disposed = true;
    _inset.dispose();
  }

  void _measure() {
    if (_disposed) return;
    var value = 0.0;
    final area = areaKey.currentContext?.findRenderObject();
    final bar = barKey.currentContext?.findRenderObject();
    if (barVisible() &&
        area is RenderBox &&
        bar is RenderBox &&
        area.hasSize &&
        bar.hasSize) {
      final areaBottom = area.localToGlobal(Offset(0, area.size.height)).dy;
      final barTop = bar.localToGlobal(Offset.zero).dy;
      value = (areaBottom - barTop).clamp(0.0, area.size.height);
    }
    _inset.value = value;
  }
}
