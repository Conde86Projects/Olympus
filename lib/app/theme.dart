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

  static ThemeData dark({bool animate = true}) {
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
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: primaryText),
        titleMedium: TextStyle(color: primaryText),
        bodyLarge: TextStyle(color: primaryText),
        bodyMedium: TextStyle(color: secondaryText),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: primaryText,
        elevation: 0,
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
