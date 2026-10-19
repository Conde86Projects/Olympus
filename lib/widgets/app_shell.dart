import 'package:flutter/material.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/core/constants/app_constants.dart';

/// Moldura padrao das telas (fora do player): cabecalho discreto com titulo,
/// navegacao e acoes. Margens laterais proporcionais a largura (spec 3.4).
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.showBack = false,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;

  /// Margem lateral para [width]: 6% presa entre 16 e 96, com piso
  /// anti-overscan de 32 no modo TV. Pura para teste direto.
  static double marginFor(double width, {required bool tvMode}) =>
      (width * 0.06).clamp(
        tvMode ? AppConstants.tvMinMargin : 16.0,
        96.0,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Na TV, menus compactos (spec 27.7): o tema 10-foot generico
    // estourava listas e configuracoes no viewport 960x540. O Theme
    // fica sempre na arvore: alternar o modo TV nao remonta a tela.
    return Theme(
      data: TvMode.of(context)
          ? PlayerTheme.tvMenus(theme, TvLayout.widthClassOf(context))
          : theme,
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final tv = TvMode.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text(title),
        actions: actions,
      ),
      // Celular: telas abertas por cima das abas reservam a barra de
      // gestos e o recorte da camera (o fim da lista e botoes como
      // Instalar ficavam embaixo dela). Desktop e TV nao tem inset.
      body: SafeArea(
        top: false,
        left: MobileMode.of(context),
        right: MobileMode.of(context),
        bottom: MobileMode.of(context),
        child: LayoutBuilder(
        builder: (context, constraints) {
          final margin = marginFor(
            constraints.maxWidth,
            tvMode: tv,
          );
          // Largura maxima centralizada: em ultrawide o conteudo nao
          // estica (Fase 3, padrao minimalista da spec 3.5).
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: margin, vertical: tv ? 8 : 16),
                child: body,
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}
