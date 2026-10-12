import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/addons/addon_details_screen.dart';
import 'package:player/features/addons/addon_install_screen.dart';
import 'package:player/features/addons/addon_repos_screen.dart';
import 'package:player/features/addons/addon_updates_screen.dart';
import 'package:player/features/addons/addons_screen.dart';
import 'package:player/features/diagnostics/diagnostics_screen.dart';
import 'package:player/features/favorites/favorites_screen.dart';
import 'package:player/features/history/history_screen.dart';
import 'package:player/features/home/home_screen.dart';
import 'package:player/features/library/library_screen.dart';
import 'package:player/features/onboarding/onboarding_screen.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/features/player/player_screen.dart';
import 'package:player/features/settings/settings_screen.dart';
import 'package:player/models/media_item.dart';

/// Gera as rotas a partir do mapa da spec 6. Telas recebem somente os
/// contratos de servico, nunca implementacoes concretas.
abstract final class AppRouter {
  static Route<dynamic>? generateRoute(
    RouteSettings settings, {
    required AppDependencies dependencies,
  }) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute(
          builder: (_) => HomeScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.player:
        final item = settings.arguments as MediaItem?;
        if (item == null) return _unknown(settings);
        return MaterialPageRoute(
          builder: (_) => PlayerScreen(
            dependencies: dependencies,
            item: item,
          ),
          settings: settings,
        );
      case AppRoutes.library:
        return MaterialPageRoute(
          builder: (_) => LibraryScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.favorites:
        return MaterialPageRoute(
          builder: (_) => FavoritesScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.history:
        return MaterialPageRoute(
          builder: (_) => HistoryScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute(
          builder: (_) => SettingsScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.openMedia:
        return MaterialPageRoute(
          builder: (_) => OpenMediaScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.onboarding:
        return MaterialPageRoute(
          builder: (_) => OnboardingScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.addons:
        return MaterialPageRoute(
          builder: (_) => AddonsScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.addonDetails:
        return MaterialPageRoute(
          builder: (_) => AddonDetailsScreen(
            dependencies: dependencies,
            addonId: settings.arguments as String? ?? '',
          ),
          settings: settings,
        );
      case AppRoutes.addonInstall:
        return MaterialPageRoute(
          builder: (_) => AddonInstallScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.addonRepos:
        return MaterialPageRoute(
          builder: (_) => AddonReposScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.addonUpdates:
        return MaterialPageRoute(
          builder: (_) => AddonUpdatesScreen(dependencies: dependencies),
          settings: settings,
        );
      case AppRoutes.diagnostics:
        return MaterialPageRoute(
          builder: (_) => DiagnosticsScreen(dependencies: dependencies),
          settings: settings,
        );
      default:
        return _unknown(settings);
    }
  }

  static Route<dynamic> _unknown(RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => const Scaffold(
        body: Center(child: Text('Tela não encontrada.')),
      ),
      settings: settings,
    );
  }
}
