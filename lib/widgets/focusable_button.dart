import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';

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
    this.destructive = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;

  /// Acao principal: preenchida só quando focada (nunca azul parado).
  final bool primary;

  /// Acao destrutiva (ex.: Remover): ganha o vermelho quando focada.
  final bool destructive;
  final FocusNode? focusNode;

  /// Cor de destaque de foco: vermelho na acao destrutiva, azul nas demais.
  Color get _focusColor => destructive ? PlayerTheme.error : PlayerTheme.accent;

  static const _idleBorder = Color(0xFF3A3A3C);
  static const _idleFill = Color(0xFF1C1C1E);

  @override
  Widget build(BuildContext context) {
    final target = TvLayout.minTarget(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final focusColor = _focusColor;
    final side = WidgetStateProperty.resolveWith<BorderSide>((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: focusColor, width: 2);
      }
      return const BorderSide(color: _idleBorder);
    });
    final background = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.focused)) {
        return primary ? focusColor : focusColor.withValues(alpha: 0.22);
      }
      return primary ? _idleFill : Colors.transparent;
    });
    final foreground = WidgetStateProperty.resolveWith<Color>((states) {
      return states.contains(WidgetState.focused)
          ? Colors.white
          : PlayerTheme.primaryText;
    });
    final iconWidget = icon == null ? const SizedBox.shrink() : Icon(icon);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: target,
        minWidth: target,
      ),
      child: OutlinedButton.icon(
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label),
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(shape),
          side: side,
          backgroundColor: background,
          foregroundColor: foreground,
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
    this.size,
    this.padding,
    this.overVideo = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool autofocus;

  /// Botao solto sobre o video (cantos do player): fundo escuro
  /// translucido. O branco a 8% do card sumia com o glifo branco sobre
  /// imagem clara (ceu, neve).
  final bool overVideo;

  /// Diametro fixo (perfil compacto da TV). Null usa o alvo minimo do
  /// contexto (44 no desktop, tokens na TV): fora da barra TV, o
  /// desenho atual segue pixel a pixel.
  final double? size;

  /// Respiro interno do [IconButton]. Null usa o padrao (8). A barra
  /// TV usa 4 para o glifo de 36 caber no botao de 44.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // O tooltip do proprio IconButton basta; um Tooltip externo duplicaria
    // a mensagem para leitores de tela.
    final target = size ?? TvLayout.minTarget(context);
    return SizedBox(
      width: target,
      height: target,
      child: IconButton(
        autofocus: autofocus,
        tooltip: tooltip,
        onPressed: onPressed,
        padding: padding ?? const EdgeInsets.all(8),
        icon: Icon(icon),
        color: PlayerTheme.primaryText,
        style: IconButton.styleFrom(
          backgroundColor: overVideo
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
