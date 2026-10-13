import 'package:flutter/material.dart';

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
