import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/router.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Raiz do aplicativo. Recebe os servicos por construtor para manter a UI
/// desacoplada das implementacoes de reproducao e armazenamento (spec 4.1).
class PlayerApp extends StatelessWidget {
  const PlayerApp({
    super.key,
    required this.preferencesService,
    required this.libraryService,
    required this.historyService,
    required this.playerService,
    required this.windowService,
    required this.addonService,
    required this.startupGuard,
    required this.diagnosticsService,
    this.mobilePlatform = false,
  });

  final PreferencesService preferencesService;
  final LibraryService libraryService;
  final HistoryService historyService;
  final MediaPlayerService playerService;
  final WindowService windowService;
  final AddonService addonService;
  final StartupGuard startupGuard;
  final DiagnosticsService diagnosticsService;

  /// Android/iOS. Com o modo TV desligado vira a composicao de
  /// celular ([MobileMode]); desktop e testes ficam no padrao (false).
  final bool mobilePlatform;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: preferencesService,
      builder: (context, _) {
        final prefs = preferencesService.current;
        return MobileMode(
          enabled: mobilePlatform && !prefs.tvMode,
          child: TvMode(
          enabled: prefs.tvMode,
          child: MaterialApp(
            title: 'Player',
            debugShowCheckedModeBanner: false,
            // Na TV, a classe de largura (spec 27.4) escolhe a faixa
            // do texto e as metricas; fora da TV, nada muda.
            builder: (context, child) {
              if (!prefs.tvMode) return child!;
              final widthClass = TvLayout.widthClassOf(context);
              final tokens = TvLayoutTokens.forClass(widthClass);
              final base = MediaQuery.textScalerOf(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: base.clamp(
                    minScaleFactor: tokens.minTextScale,
                    maxScaleFactor: tokens.maxTextScale,
                  ),
                ),
                child: _TvClassTheme(
                    widthClass: widthClass, child: child!),
              );
            },
            theme: PlayerTheme.dark(
                animate: prefs.animations, tvMode: prefs.tvMode),
          darkTheme: PlayerTheme.dark(
              animate: prefs.animations, tvMode: prefs.tvMode),
          themeMode: prefs.theme == AppThemeMode.system
              ? ThemeMode.system
              : ThemeMode.dark,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates:
              GlobalMaterialLocalizations.delegates,
          initialRoute: prefs.showOnboarding
              ? AppRoutes.onboarding
              : AppRoutes.home,
          onGenerateRoute: (settings) => AppRouter.generateRoute(
            settings,
            dependencies: AppDependencies(
              preferencesService: preferencesService,
              libraryService: libraryService,
              historyService: historyService,
              playerService: playerService,
              windowService: windowService,
              addonService: addonService,
              startupGuard: startupGuard,
              diagnosticsService: diagnosticsService,
            ),
          ),
          ),
          ),
        );
      },
    );
  }
}

/// Dependencias compartilhadas entre rotas.
class AppDependencies {
  const AppDependencies({
    required this.preferencesService,
    required this.libraryService,
    required this.historyService,
    required this.playerService,
    required this.windowService,
    required this.addonService,
    required this.startupGuard,
    required this.diagnosticsService,
  });

  final PreferencesService preferencesService;
  final LibraryService libraryService;
  final HistoryService historyService;
  final MediaPlayerService playerService;
  final WindowService windowService;
  final AddonService addonService;
  final StartupGuard startupGuard;
  final DiagnosticsService diagnosticsService;
}

/// Aplica as metricas da classe de largura sobre o tema (spec 27.4).
/// Widget separado de proposito: o contexto do builder do MaterialApp
/// nao alcanca o tema aplicado, entao o override envolve o filho.
class _TvClassTheme extends StatelessWidget {
  const _TvClassTheme({required this.widthClass, required this.child});

  final TvWidthClass widthClass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (widthClass) {
      TvWidthClass.compact => 28.0,
      TvWidthClass.normal => 32.0,
      TvWidthClass.big => 36.0,
    };
    final appBar = switch (widthClass) {
      TvWidthClass.compact => 64.0,
      TvWidthClass.normal => 72.0,
      TvWidthClass.big => 80.0,
    };
    final track = switch (widthClass) {
      TvWidthClass.compact => 5.0,
      TvWidthClass.normal => 6.0,
      TvWidthClass.big => 7.0,
    };
    final thumb = switch (widthClass) {
      TvWidthClass.compact => 12.0,
      TvWidthClass.normal => 14.0,
      TvWidthClass.big => 16.0,
    };
    final listH = switch (widthClass) {
      TvWidthClass.compact => 20.0,
      TvWidthClass.normal => 24.0,
      TvWidthClass.big => 28.0,
    };
    final listV = switch (widthClass) {
      TvWidthClass.compact => 8.0,
      TvWidthClass.normal => 10.0,
      TvWidthClass.big => 12.0,
    };
    return Theme(
      data: theme.copyWith(
        iconTheme: theme.iconTheme.copyWith(size: icon),
        appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: appBar),
        sliderTheme: theme.sliderTheme.copyWith(
          trackHeight: track,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumb),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          contentPadding: EdgeInsets.symmetric(horizontal: listH),
          minVerticalPadding: listV,
        ),
      ),
      child: child,
    );
  }
}
