import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/home/home_sections.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';
import 'package:player/widgets/app_toast.dart';

/// Tela inicial (spec 8): "Continuar assistindo", abrir arquivo/link e acesso
/// a biblioteca, favoritos, historico e configuracoes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    // O menu acompanha a escolha de destinos em Configuracoes.
    return AnimatedBuilder(
      animation: dependencies.preferencesService,
      builder: (context, _) => _buildScreen(
          context, dependencies.preferencesService.current.hiddenDestinations),
    );
  }

  Widget _buildScreen(BuildContext context, List<MainDestination> hidden) {
    bool shown(MainDestination d) => !hidden.contains(d);
    final guard = dependencies.startupGuard;
    // No celular, Biblioteca, Add-ons, Favoritos e Configuracoes moram
    // na navegacao inferior ([MobileShell]); o Historico fica aqui.
    final mobile = MobileMode.of(context);
    // T7: no desktop o Início mostra fileiras e ocupa a janela toda;
    // celular e TV seguem na lista vertical de antes.
    final desktop = !mobile && !TvLayout.isTv(context);
    return AppShell(
      title: 'Olympus',
      showLogo: true,
      maxWidth: desktop ? null : 1080,
      actions: [
        if (!mobile && shown(MainDestination.library))
        IconButton(
          tooltip: 'Biblioteca',
          icon: const Icon(Icons.video_library_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.library),
        ),
        if (!mobile && shown(MainDestination.addons))
        IconButton(
          tooltip: 'Add-ons',
          icon: const Icon(Icons.extension_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addons),
        ),
        if (!mobile && shown(MainDestination.favorites))
        IconButton(
          tooltip: 'Favoritos',
          icon: const Icon(Icons.favorite_outline),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.favorites),
        ),
        if (shown(MainDestination.history))
        IconButton(
          tooltip: 'Histórico',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.history),
        ),
        if (!mobile)
        IconButton(
          tooltip: 'Configurações',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
      ],
      body: desktop
          ? _desktopBody(context)
          : _classicBody(context, guard),
    );
  }

  /// Lista vertical de antes (celular e TV, T7): "Continuar
  /// assistindo" com a regra movida para [continueWatchingItems].
  Widget _classicBody(BuildContext context, StartupGuard guard) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    return Column(
      children: [
        AnimatedBuilder(
          animation: guard,
          builder: (context, _) => guard.safeMode
              ? _SafeModeBanner(guard: guard)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([library, history]),
            builder: (context, _) {
              final resume = continueWatchingItems(
                entries: history.entries,
                byId: itemsById(library.items),
              );
              if (resume.isEmpty) return _empty(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continuar assistindo',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: resume.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = resume[index];
                        return MediaCard(
                          item: item,
                          autofocus: index == 0,
                          onTap: () => _play(context, item),
                          onRestart: () =>
                              _play(context, item, fromStart: true),
                          onToggleFavorite: () =>
                              library.toggleFavorite(item.id),
                          onRemove: () =>
                              _removeFromHistory(context, item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _openActions(context),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Fileiras horizontais do desktop (T7): Continuar assistindo,
  /// Arquivos locais e Favoritos, na largura livre da janela. Os
  /// cartões são os mesmos (pôster sem aumentar) e a fileira mede
  /// a altura exata do cartão mais alto (sem número mágico que a
  /// escala de texto estouraria).
  static const _cardWidth = 320.0;

  Widget _desktopBody(BuildContext context) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    final guard = dependencies.startupGuard;
    return Column(
      children: [
        AnimatedBuilder(
          animation: guard,
          builder: (context, _) => guard.safeMode
              ? _SafeModeBanner(guard: guard)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([library, history]),
            builder: (context, _) {
              final sections = homeSections(
                entries: history.entries,
                items: library.items,
              );
              if (sections.isEmpty) return _empty(context);
              return ListView.separated(
          itemCount: sections.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 24),
          itemBuilder: (context, s) {
            if (s >= sections.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _openActions(context),
              );
            }
            final section = sections[s];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(section.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < section.items.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          SizedBox(
                            width: _cardWidth,
                            child: Builder(builder: (context) {
                              final item = section.items[i];
                              return MediaCard(
                                item: item,
                                autofocus: s == 0 &&
                                    i == 0 &&
                                    ModalRoute.of(context)?.isCurrent == true,
                                onTap: () => _play(context, item),
                                onRestart: () => _play(context, item,
                                    fromStart: true),
                                onToggleFavorite: () =>
                                    library.toggleFavorite(item.id),
                                onRemove: s == 0
                                    ? () =>
                                        _removeFromHistory(context, item)
                                    : null,
                              );
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  ),
  ],
);
  }

  /// F3 (Fase 4b): confirma antes de tirar do histórico; o item
  /// continua na biblioteca.
  Future<void> _removeFromHistory(BuildContext context, MediaItem item) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Remover do histórico?',
      message:
          "'${item.title}' sai do histórico. O item continua na biblioteca.",
    );
    if (confirmed) dependencies.historyService.remove(item.id);
  }

  Widget _empty(BuildContext context) {
    return EmptyState(
      icon: Icons.play_circle_outline,
      title: 'Nenhum vídeo por aqui ainda',
      message:
          'Ainda não há vídeos aqui. Abra um arquivo ou um link para começar.',
      actions: [
        FocusableButton(
          label: 'Abrir arquivo',
          icon: Icons.folder_open,
          primary: true,
          autofocus: true,
          onPressed: () => _openMedia(context, OpenMediaTab.file),
        ),
        FocusableButton(
          label: 'Abrir link',
          icon: Icons.link,
          onPressed: () => _openMedia(context, OpenMediaTab.link),
        ),
      ],
    );
  }

  Widget _openActions(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: [
        FocusableButton(
          label: 'Abrir arquivo',
          icon: Icons.folder_open,
          onPressed: () => _openMedia(context, OpenMediaTab.file),
        ),
        FocusableButton(
          label: 'Abrir link',
          icon: Icons.link,
          onPressed: () => _openMedia(context, OpenMediaTab.link),
        ),
      ],
    );
  }

  void _play(BuildContext context, MediaItem item, {bool fromStart = false}) {
    final target = fromStart ? item.copyWith(lastPosition: () => null) : item;
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: target);
  }

  void _openMedia(BuildContext context, OpenMediaTab tab) {
    Navigator.of(context).pushNamed(
      AppRoutes.openMedia,
      arguments: OpenMediaArgs(tab: tab),
    );
  }
}

/// Faixa de modo seguro (spec 6.1): informa o motivo, oferece desativar
/// a ultima alteracao de add-on e some so com o reinicio.
class _SafeModeBanner extends StatefulWidget {
  const _SafeModeBanner({required this.guard});

  final StartupGuard guard;

  @override
  State<_SafeModeBanner> createState() => _SafeModeBannerState();
}

class _SafeModeBannerState extends State<_SafeModeBanner> {
  late Future<LastAddonChange?> _change;

  @override
  void initState() {
    super.initState();
    _change = widget.guard.readLastChange();
    widget.guard.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.guard.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _change = widget.guard.readLastChange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guard = widget.guard;
    final reason = guard.safeModeReason == SafeModeReason.manual
        ? 'Modo seguro ativado manualmente: add-ons não carregados.'
        : 'Modo seguro: add-ons não carregados '
            '(${guard.consecutiveFailures} falhas no arranque).';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber,
                  size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20,
                  color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FutureBuilder<LastAddonChange?>(
                  future: _change,
                  builder: (context, snapshot) {
                    final change = snapshot.data;
                    if (change == null) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Última alteração: ${change.name}.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FocusableButton(
                          label: 'Desativar última alteração',
                          icon: Icons.toggle_off,
                          onPressed: () => _disable(context),
                        ),
                      ],
                    );
                  },
                ),
                FocusableButton(
                  label: 'Diagnóstico',
                  icon: Icons.health_and_safety,
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.diagnostics,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disable(BuildContext context) async {
    final disabled = await widget.guard.disableLastChange();
    if (!context.mounted) return;
    showAppToast(
      context,
      disabled
          ? 'Última alteração desativada. Reinicie para sair do modo seguro.'
          : 'Nada a desativar.',
    );
  }
}
