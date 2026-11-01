import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/main_navigation.dart';
import 'package:player/app/theme.dart';
import 'package:player/features/addons/addons_screen.dart';
import 'package:player/features/favorites/favorites_screen.dart';
import 'package:player/features/home/home_screen.dart';
import 'package:player/features/library/library_screen.dart';
import 'package:player/features/settings/settings_screen.dart';
import 'package:player/models/preferences.dart';

/// Raiz do celular ([MobileMode]): navegacao inferior com as telas
/// principais. Cada aba mantem o proprio estado (rolagem, filtros) ao
/// trocar. Telas de detalhe e o player abrem por cima, como antes.
/// Desktop e TV nao passam por aqui: seguem na [HomeScreen] com a
/// barra superior.
/// Abas da barra inferior, na ordem de exibicao (rotulos curtos: cabem
/// em 360 dp). A aba ativa e guardada por identidade, nao por posicao,
/// para esconder um destino nao trocar a tela do usuario.
enum MobileTab {
  home(Icons.home_outlined, Icons.home, 'Início'),
  library(Icons.video_library_outlined, Icons.video_library, 'Biblioteca',
      MainDestination.library),
  favorites(Icons.favorite_outline, Icons.favorite, 'Favoritos',
      MainDestination.favorites),
  addons(Icons.extension_outlined, Icons.extension, 'Add-ons',
      MainDestination.addons),
  settings(Icons.settings_outlined, Icons.settings, 'Ajustes');

  const MobileTab(this.icon, this.selectedIcon, this.label, [this.hideable]);
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Destino que o usuario pode esconder; null = sempre visivel.
  final MainDestination? hideable;
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  MobileTab _current = MobileTab.home;

  /// Abas ja visitadas: montadas sob demanda e mantidas vivas depois.
  final _visited = <MobileTab>{MobileTab.home};

  @override
  void initState() {
    super.initState();
    MainNavigation.request.addListener(_onRequest);
  }

  @override
  void dispose() {
    MainNavigation.request.removeListener(_onRequest);
    super.dispose();
  }

  /// Pedido vindo de fora (fim do video): troca para a aba pedida.
  void _onRequest() {
    final target = MainNavigation.request.value;
    if (target == null) return;
    MainNavigation.request.value = null;
    _select(switch (target) {
      ExitTarget.home => MobileTab.home,
      ExitTarget.library => MobileTab.library,
    });
  }

  Widget _page(MobileTab tab) {
    final deps = widget.dependencies;
    return switch (tab) {
      MobileTab.home => HomeScreen(dependencies: deps),
      MobileTab.library => LibraryScreen(dependencies: deps),
      MobileTab.favorites => FavoritesScreen(dependencies: deps),
      MobileTab.addons => AddonsScreen(dependencies: deps),
      MobileTab.settings => SettingsScreen(dependencies: deps),
    };
  }

  /// Abas visiveis agora, na ordem da barra.
  List<MobileTab> _visibleTabs(List<MainDestination> hidden) => [
        for (final tab in MobileTab.values)
          if (tab.hideable == null || !hidden.contains(tab.hideable)) tab,
      ];

  void _select(MobileTab tab) {
    setState(() {
      _current = tab;
      _visited.add(tab);
    });
    // Primeira seta deterministica: se o foco se perdeu na troca
    // (no da aba antiga fora de cena), ancora de novo apos o rebuild.
    // Foco valido nao e roubado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = FocusManager.instance.primaryFocus;
      if (current == null || current.context == null) {
        FocusScope.of(context).nextFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.dependencies.preferencesService;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final tabs = _visibleTabs(prefs.current.hiddenDestinations);
        // A aba ativa so some se for escondida estando nela (por outra
        // rota); nesse caso cai no Inicio.
        final active = tabs.contains(_current) ? _current : MobileTab.home;
        return PopScope(
          // Voltar do sistema fora do Inicio volta ao Inicio; no Inicio,
          // sai do app como de costume.
          canPop: active == MobileTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _select(MobileTab.home);
          },
          child: Scaffold(
            body: IndexedStack(
              index: MobileTab.values.indexOf(active),
              children: [
                for (final tab in MobileTab.values)
                  _visited.contains(tab) || tab == active
                      ? _page(tab)
                      : const SizedBox.shrink(),
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
                selectedIndex: tabs.indexOf(active),
                onDestinationSelected: (i) => _select(tabs[i]),
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
