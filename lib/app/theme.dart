import 'package:flutter/material.dart';
import 'package:player/app/tv_layout.dart';

/// Tema inicial (spec 3.3): fundo quase preto, texto branco suave, cantos
/// arredondados. A cor de destaque da marca ainda nao foi definida (item 3
/// das pendencias) e usa um azul neutro temporario.
abstract final class PlayerTheme {
  static const background = Color(0xFF0E0E10);
  static const surface = Color(0xB3242426);
  static const primaryText = Color(0xFFF2F2F3);
  static const secondaryText = Color(0xFFB8B8BE);
  static const accent = Color(0xFF4C8DFF);
  static const error = Color(0xFFD06060);
  static const success = Color(0xFF5FA86B);

  /// Superficie neutra do player (spec 3.5): sem neon — controles,
  /// selecao e foco em branco (selecionado = branco 10%). Aplica-se aos
  /// controles e ao painel flutuante; o restante do app mantem o tema.
  static ThemeData playerSurface(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      primary: primaryText,
      onPrimary: background,
      secondaryContainer: Colors.white.withValues(alpha: 0.10),
      onSecondaryContainer: primaryText,
    );
    return base.copyWith(
      colorScheme: scheme,
      focusColor: Colors.white.withValues(alpha: 0.25),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.1),
        thickness: 1,
        space: 1,
        indent: 16,
        endIndent: 16,
      ),
    );
  }

  /// Densidade das telas de menu na TV (inicio, configuracoes, fontes,
  /// diagnostico...): aplicada pelo [AppShell] so no modo TV. A TCL
  /// 1080p em 320 dpi mostra 960x540 logicos; com as metricas padrao
  /// do Material (linhas de 56-72, appbar 72, icones 32, titulos 22)
  /// os menus estouravam. Mesma linguagem do player aprovado: icones
  /// 20-24, texto de linha 14-17, linhas ~40. O player nao usa o
  /// AppShell e segue intacto; desktop nunca passa por aqui.
  static ThemeData tvMenus(ThemeData base, TvWidthClass widthClass) {
    double pick(double compact, double normal, double big) =>
        switch (widthClass) {
          TvWidthClass.compact => compact,
          TvWidthClass.normal => normal,
          TvWidthClass.big => big,
        };
    final icon = pick(20, 22, 24);
    final text = base.textTheme;
    TextStyle? sized(TextStyle? style, double size) =>
        (style ?? const TextStyle()).copyWith(fontSize: size);
    return base.copyWith(
      iconTheme: base.iconTheme.copyWith(size: icon),
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: pick(48, 52, 60),
        iconTheme: IconThemeData(size: icon, color: primaryText),
        actionsIconTheme: IconThemeData(size: icon, color: primaryText),
        // Derivados do textTheme (inherit: false): a troca animada
        // de tema ao alternar o modo TV so interpola estilos iguais.
        titleTextStyle: sized(text.titleLarge, pick(18, 19, 21))
            ?.copyWith(fontWeight: FontWeight.w500, color: primaryText),
      ),
      textTheme: text.copyWith(
        titleLarge: sized(text.titleLarge, pick(18, 20, 22)),
        titleMedium: sized(text.titleMedium, pick(14, 15, 17)),
        titleSmall: sized(text.titleSmall, pick(13, 13, 15)),
        bodyLarge: sized(text.bodyLarge, pick(14, 15, 16)),
        bodyMedium: sized(text.bodyMedium, pick(12, 13, 14)),
        bodySmall: sized(text.bodySmall, pick(11, 12, 13)),
        labelLarge: sized(text.labelLarge, pick(13, 14, 15)),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        visualDensity: const VisualDensity(vertical: -4),
        contentPadding: EdgeInsets.symmetric(horizontal: pick(12, 16, 20)),
        minVerticalPadding: pick(0, 0, 2),
        horizontalTitleGap: 12,
        minLeadingWidth: 32,
        iconColor: secondaryText,
        titleTextStyle: sized(text.bodyLarge, pick(13, 14, 16))
            ?.copyWith(color: primaryText),
        subtitleTextStyle: sized(text.bodyMedium, pick(12, 12, 14))
            ?.copyWith(color: secondaryText),
        leadingAndTrailingTextStyle: sized(text.labelSmall, pick(12, 13, 14))
            ?.copyWith(color: secondaryText),
      ),
      switchTheme: base.switchTheme.copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // Mesmo trilho fino aprovado na barra do player.
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        space: 8,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(isDense: true),
    );
  }

  /// Interruptor padrão do app (TV, desktop e celular): o Switch do
  /// Material 3 tem 52x32 fixos (sem parametro de tamanho) e, com
  /// trilho azul cheio, chamava mais atencao que o texto. Usamos o
  /// desenho classico (trilho 33x14, dedao 20) com cores neutras,
  /// aprovado na TV e estendido as demais plataformas (19/10/2026);
  /// aplicado ao redor dos interruptores via [AppSwitchTheme].
  static ThemeData appSwitch(ThemeData base) => base.copyWith(
        // So o desenho do Switch muda; sem alternativa nao depreciada.
        // ignore: deprecated_member_use
        useMaterial3: false,
        switchTheme: SwitchThemeData(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? accent : secondaryText,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        // O modo classico tambem troca o texto da linha (titulo em
        // negrito do M2). Fixa o estilo atual (M3) para a linha com
        // interruptor ficar igual as demais; na TV os menus compactos
        // ja definem os seus e prevalecem.
        listTileTheme: base.listTileTheme.copyWith(
          titleTextStyle: base.listTileTheme.titleTextStyle ??
              base.textTheme.bodyLarge,
          subtitleTextStyle: base.listTileTheme.subtitleTextStyle ??
              base.textTheme.bodyMedium,
        ),
      );

  /// Dialogos na TV: titulo e corpo no tamanho dos menus compactos
  /// (o dialogo nasce no Navigator raiz, fora do [AppShell]).
  static DialogThemeData tvDialogs(TvWidthClass widthClass) {
    final big = widthClass == TvWidthClass.big;
    return DialogThemeData(
      titleTextStyle: TextStyle(
        fontSize: big ? 20 : 18,
        fontWeight: FontWeight.w500,
        color: primaryText,
      ),
      contentTextStyle:
          TextStyle(fontSize: big ? 16 : 14, color: secondaryText),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
    );
  }

  /// `tvMode` aplica a base 10-foot da classe normal (icones, appbar,
  /// linhas maiores); sem ele, o desenho atual, sem mudanca.
  static ThemeData dark({bool animate = true, bool tvMode = false}) {
    const scheme = ColorScheme.dark(
      primary: accent,
      surface: background,
      error: error,
      onPrimary: Colors.white,
      onSurface: primaryText,
      onError: Colors.white,
    );
    const animated = FadeUpwardsPageTransitionsBuilder();
    const instant = _InstantPageTransitionsBuilder();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      focusColor: accent.withValues(alpha: 0.25),
      // Icones convergiram: 24 no desktop e na TV (verificado na TCL).
      iconTheme: const IconThemeData(size: 24),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: primaryText),
        titleMedium: TextStyle(color: primaryText),
        bodyLarge: TextStyle(color: primaryText),
        bodyMedium: TextStyle(color: secondaryText),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: primaryText,
        elevation: 0,
        toolbarHeight: tvMode ? 72 : null,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: tvMode ? 6 : 4,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: tvMode ? 14 : 10,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: tvMode ? 24 : 16,
        ),
        minVerticalPadding: tvMode ? 10 : 4,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: animate ? animated : instant,
          TargetPlatform.linux: animate ? animated : instant,
          TargetPlatform.macOS: animate ? animated : instant,
          TargetPlatform.android: animate ? animated : instant,
        },
      ),
    );
  }
}

/// Transicao instantanea para a preferencia de animacoes desligada
/// (spec 16). Sem fade, sem deslize: troca direta.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
