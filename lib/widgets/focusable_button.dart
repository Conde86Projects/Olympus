import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_mode.dart';

/// Botao com foco sempre visivel (spec 18: navegacao por controle remoto).
/// Area minima de 44 px (spec 3.4) e rotulo para leitores de tela.
class FocusableButton extends StatelessWidget {
  const FocusableButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.primary = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool primary;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final target = TvMode.minTarget(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: target,
        minWidth: target,
      ),
      child: primary
          ? FilledButton.icon(
              autofocus: autofocus,
              focusNode: focusNode,
              onPressed: onPressed,
              icon: icon == null ? const SizedBox.shrink() : Icon(icon),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: PlayerTheme.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : OutlinedButton.icon(
              autofocus: autofocus,
              focusNode: focusNode,
              onPressed: onPressed,
              icon: icon == null ? const SizedBox.shrink() : Icon(icon),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: PlayerTheme.primaryText,
                side: const BorderSide(color: Color(0xFF3A3A3C)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }
}

/// Botao circular para acoes rapidas do player (spec 3.4).
class RoundPlayerButton extends StatelessWidget {
  const RoundPlayerButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // O tooltip do proprio IconButton basta; um Tooltip externo duplicaria
    // a mensagem para leitores de tela.
    final target = TvMode.minTarget(context);
    return SizedBox(
      width: target,
      height: target,
      child: IconButton(
        autofocus: autofocus,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: PlayerTheme.primaryText,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
