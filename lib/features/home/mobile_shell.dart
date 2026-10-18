import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/theme.dart';
import 'package:player/features/addons/addons_screen.dart';
import 'package:player/features/favorites/favorites_screen.dart';
import 'package:player/features/home/home_screen.dart';
import 'package:player/features/library/library_screen.dart';
import 'package:player/features/settings/settings_screen.dart';

/// Raiz do celular ([MobileMode]): navegacao inferior com as telas
/// principais. Cada aba mantem o proprio estado (rolagem, filtros) ao
/// trocar. Telas de detalhe e o player abrem por cima, como antes.
/// Desktop e TV nao passam por aqui: seguem na [HomeScreen] com a
/// barra superior.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.dependencies});

  final AppDependencies dependencies;

  /// Abas na ordem da barra (rotulos curtos: cabem em 360 dp).
  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Início',
    ),
    NavigationDestination(
      icon: Icon(Icons.video_library_outlined),
      selectedIcon: Icon(Icons.video_library),
      label: 'Biblioteca',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_outline),
      selectedIcon: Icon(Icons.favorite),
      label: 'Favoritos',
    ),
    NavigationDestination(
      icon: Icon(Icons.extension_outlined),
      selectedIcon: Icon(Icons.extension),
      label: 'Add-ons',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Ajustes',
    ),
  ];

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;

  /// Abas ja visitadas: montadas sob demanda e mantidas vivas depois.
  final _visited = <int>{0};

  Widget _page(int index) {
    final deps = widget.dependencies;
    return switch (index) {
      0 => HomeScreen(dependencies: deps),
      1 => LibraryScreen(dependencies: deps),
      2 => FavoritesScreen(dependencies: deps),
      3 => AddonsScreen(dependencies: deps),
      _ => SettingsScreen(dependencies: deps),
    };
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Voltar do sistema fora do Inicio volta ao Inicio; no Inicio,
      // sai do app como de costume.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < MobileShell.destinations.length; i++)
              _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
        // Aba ativa na cor de destaque do app (o padrao do Material
        // saia verde-agua, fora da paleta).
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: PlayerTheme.accent.withValues(alpha: 0.35),
            iconTheme: const WidgetStatePropertyAll(
                IconThemeData(color: PlayerTheme.primaryText)),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: MobileShell.destinations,
          ),
        ),
      ),
    );
  }
}
