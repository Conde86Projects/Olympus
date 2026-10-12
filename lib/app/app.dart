import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:player/app/router.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
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
  });

  final PreferencesService preferencesService;
  final LibraryService libraryService;
  final HistoryService historyService;
  final MediaPlayerService playerService;
  final WindowService windowService;
  final AddonService addonService;
  final StartupGuard startupGuard;
  final DiagnosticsService diagnosticsService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: preferencesService,
      builder: (context, _) {
        final prefs = preferencesService.current;
        return TvMode(
          enabled: prefs.tvMode,
          child: MaterialApp(
            title: 'Player',
            debugShowCheckedModeBanner: false,
            // Na TV o texto cresce um pouco (10-foot), sem passar
            // por cima da escala de acessibilidade do SO.
            builder: (context, child) {
              if (!prefs.tvMode) return child!;
              final base = MediaQuery.textScalerOf(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: base.clamp(
                    minScaleFactor: 1.15,
                    maxScaleFactor: 1.3,
                  ),
                ),
                child: child!,
              );
            },
            theme: PlayerTheme.dark(animate: prefs.animations),
          darkTheme: PlayerTheme.dark(animate: prefs.animations),
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
