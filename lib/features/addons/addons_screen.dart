import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';

/// Gerenciador de add-ons (spec 6.1, Fase 5): instalados com seus
/// estados. Detalhes, instalacao e repositorios vivem em telas proprias.
class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final addons = dependencies.addonService;
    return AppShell(
      title: 'Add-ons',
      showBack: true,
      actions: [
        _UpdatesAction(addons: addons),
        IconButton(
          tooltip: 'Repositórios',
          icon: const Icon(Icons.storage),
          onPressed: () => Navigator.of(context).pushNamed(
            AppRoutes.addonRepos,
          ),
        ),
        IconButton(
          tooltip: 'Instalar add-on',
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.of(context).pushNamed(
            AppRoutes.addonInstall,
          ),
        ),
      ],
      body: AnimatedBuilder(
        animation: addons,
        builder: (context, _) {
          final items = addons.addons;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.extension_outlined,
              title: 'Nenhum add-on instalado',
              message:
                  'Add-ons adicionam catálogos e fontes de mídia. '
                  'Instale a partir de um repositório ou manifesto.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return _AddonTile(
                info: item,
                autofocus: index == 0,
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.addonDetails,
                  arguments: item.manifest.id,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Atalho para a tela de atualizacoes, com ponto quando ha pendencia.
/// O ponto e redundante com o texto da lista (nunca so cor).
class _UpdatesAction extends StatelessWidget {
  const _UpdatesAction({required this.addons});

  final AddonService addons;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: addons,
      builder: (context, _) {
        final hasPending =
            addons.addons.any((info) => info.updateAvailable);
        return Badge(
          isLabelVisible: hasPending,
          child: IconButton(
            tooltip: 'Atualizações',
            icon: const Icon(Icons.system_update),
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.addonUpdates,
            ),
          ),
        );
      },
    );
  }
}

/// Linha de um add-on: estado (icone + texto), nome, versao e autor.
/// Focavel por teclado/controle remoto (spec 18).
class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.info,
    required this.onTap,
    this.autofocus = false,
  });

  final AddonInfo info;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateColor = info.state == AddonState.error
        ? theme.colorScheme.error
        : theme.textTheme.bodyMedium?.color;
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(addonStateIcon(info.state),
                  size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconPrimary : 28,
                  color: stateColor),
              SizedBox(width: TvLayout.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.manifest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${info.manifest.version} · ${info.manifest.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.updateAvailable
                          ? '${addonStateLabel(info.state)} · '
                              'Atualização disponível'
                          : addonStateLabel(info.state),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: stateColor),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
