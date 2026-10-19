import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';

/// Aviso curto do app (estilo toast): cartão escuro arredondado no topo
/// da tela, centralizado e com largura limitada, com ícone de sucesso
/// ou de erro. Cai do topo com um leve quique, fica [AppToast.hold] na
/// tela e sobe acelerando, como se fosse puxado. Substitui a faixa do
/// SnackBar, que ocupava a largura toda colada no rodapé.
void showAppToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  // Um aviso por vez: o novo substitui o anterior na hora.
  AppToast._current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastView(
      message: message,
      error: error,
      onDone: () {
        if (identical(AppToast._current, entry)) AppToast._current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  AppToast._current = entry;
  overlay.insert(entry);
}

/// Medidas e tempos do [showAppToast] (testes conferem o desenho).
abstract final class AppToast {
  static const maxWidth = 440.0;
  static const background = Color(0xF2242428);

  /// Queda (com quique), permanência e subida.
  static const drop = Duration(milliseconds: 520);
  static const hold = Duration(seconds: 4);
  static const lift = Duration(milliseconds: 320);

  /// Chave do cartão (testes medem posição e largura).
  static const cardKey = ValueKey('app-toast-card');

  static OverlayEntry? _current;
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.error,
    required this.onDone,
  });

  final String message;
  final bool error;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppToast.drop,
    reverseDuration: AppToast.lift,
  );

  // Entrada: cai do topo e quica de leve (easeOutBack). Saída: sobe
  // acelerando (easeIn), "puxado" para cima.
  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (!mounted) return;
      _holdTimer = Timer(AppToast.hold, () {
        if (!mounted) return;
        _controller.reverse().whenComplete(() {
          if (mounted) widget.onDone();
        });
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final color = widget.error ? PlayerTheme.error : PlayerTheme.accent;
    final card = Material(
      color: AppToast.background,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              widget.error ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: PlayerTheme.primaryText,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // Não bloqueia a tela: toques e foco seguem para o app.
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: SizedBox(
                key: AppToast.cardKey,
                width: math.min(AppToast.maxWidth, screen - 32),
                child: AnimatedBuilder(
                  animation: _slide,
                  // Fora da tela (acima) em 0; no lugar em 1.
                  builder: (context, child) => FractionalTranslation(
                    translation: Offset(0, (_slide.value - 1) * 1.6),
                    child: Opacity(
                      opacity: _controller.value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
