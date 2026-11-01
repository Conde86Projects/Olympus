import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/features/addons/addon_install_screen.dart';
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
      ],
      body: AnimatedBuilder(
        animation: addons,
        builder: (context, _) {
          final items = addons.addons;
          // Entradas do hub (T6) antes da lista. O primeiro add-on segue
          // com o foco inicial; sem add-on, a primeira entrada recebe.
          final children = <Widget>[
            _EntryTile(
              icon: Icons.storage_outlined,
              autofocus: items.isEmpty,
              title: 'Instalar de repositório',
              subtitle: 'Catálogos publicados por repositórios.',
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.addonRepos,
              ),
            ),
            const SizedBox(height: 8),
            _EntryTile(
              icon: Icons.archive_outlined,
              title: 'Instalar de zip',
              subtitle: 'Arquivo do aparelho ou link.',
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.addonInstall,
                arguments:
                    const AddonInstallArgs(source: AddonInstallSource.zip),
              ),
            ),
            const SizedBox(height: 16),
            // Mesma margem de 4 do Card, para alinhar com os cartões.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Meus add-ons (${items.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
          ];
          if (items.isEmpty) {
            children.add(
              const EmptyState(
                icon: Icons.extension_outlined,
                title: 'Nenhum add-on instalado',
                message: 'Add-ons adicionam catálogos e fontes de mídia. '
                    'Instale de um repositório ou de um zip nas opções acima.',
              ),
            );
          } else {
            for (var index = 0; index < items.length; index++) {
              if (index > 0) children.add(const SizedBox(height: 8));
              final item = items[index];
              children.add(
                _AddonTile(
                  info: item,
                  autofocus: index == 0,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.addonDetails,
                    arguments: item.manifest.id,
                  ),
                ),
              );
            }
          }
          return ListView(
            children: children,
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
        final hasPending = addons.addons.any((info) => info.updateAvailable);
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

/// Entrada do hub (T6): cartao focavel por toque, teclado e
/// controle remoto que leva direto ao fluxo.
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  final bool autofocus;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Icon(
                icon,
                size: TvLayout.isTv(context)
                    ? TvLayout.tokensOf(context).iconPrimary
                    : 28,
              ),
              SizedBox(width: TvLayout.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
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
                  size: TvLayout.isTv(context)
                      ? TvLayout.tokensOf(context).iconPrimary
                      : 28,
                  color: addonStateColor(context, info.state)),
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
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
