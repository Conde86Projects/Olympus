import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';

/// Tela inicial (spec 8): "Continuar assistindo", abrir arquivo/link e acesso
/// a biblioteca, favoritos, historico e configuracoes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    final guard = dependencies.startupGuard;
    return AppShell(
      title: 'Player',
      actions: [
        IconButton(
          tooltip: 'Biblioteca',
          icon: const Icon(Icons.video_library_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.library),
        ),
        IconButton(
          tooltip: 'Add-ons',
          icon: const Icon(Icons.extension_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addons),
        ),
        IconButton(
          tooltip: 'Favoritos',
          icon: const Icon(Icons.favorite_outline),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.favorites),
        ),
        IconButton(
          tooltip: 'Histórico',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.history),
        ),
        IconButton(
          tooltip: 'Configurações',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
      ],
      body: Column(
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
                final resume = _continueWatching();
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
                            onRemove: () async {
                              // F3 (Fase 4b): confirma antes de tirar do
                              // histórico; o item continua na biblioteca.
                              final confirmed = await confirmDestructiveAction(
                                context,
                                title: 'Remover do histórico?',
                                message:
                                    "'${item.title}' sai do histórico. O item continua na biblioteca.",
                              );
                              if (confirmed) history.remove(item.id);
                            },
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
      ),
    );
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

  /// Junta historico + biblioteca: itens com posicao salva primeiro, depois
  /// os mais recentes. Limite em [AppConstants.continueWatchingLimit].
  List<MediaItem> _continueWatching() {
    final library = dependencies.libraryService;
    final entries = dependencies.historyService.entries;
    final seen = <String>{};
    final result = <MediaItem>[];
    for (final entry in entries) {
      if (!seen.add(entry.mediaId)) continue;
      final item = library.findById(entry.mediaId);
      if (item == null || entry.completed) continue;
      result.add(item.copyWith(lastPosition: () => entry.position));
      if (result.length >= AppConstants.continueWatchingLimit) break;
    }
    result.sort((a, b) {
      final ra = a.isResumable ? 0 : 1;
      final rb = b.isResumable ? 0 : 1;
      if (ra != rb) return ra.compareTo(rb);
      return (b.lastPlayedAt ?? b.addedAt)
          .compareTo(a.lastPlayedAt ?? a.addedAt);
    });
    return result;
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
                  size: 20, color: theme.colorScheme.error),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(disabled
            ? 'Última alteração desativada. Reinicie para sair do modo seguro.'
            : 'Nada a desativar.'),
      ),
    );
  }
}
