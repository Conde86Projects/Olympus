import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';

/// Historico (spec 15.3): continuar, recomecar, remover e limpar tudo
/// (com confirmacao). Limpar nunca apaga arquivos locais.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final history = dependencies.historyService;
    final library = dependencies.libraryService;
    return AppShell(
      title: 'Histórico',
      showBack: true,
      actions: [
        IconButton(
          tooltip: 'Limpar histórico',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmClear(context),
        ),
      ],
      body: AnimatedBuilder(
        animation: Listenable.merge([history, library]),
        builder: (context, _) {
          final entries = history.entries
              .where((e) => library.findById(e.mediaId) != null)
              .toList();
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Histórico vazio',
              message: 'Os vídeos assistidos aparecem aqui.',
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final item =
                  library.findById(entry.mediaId)!.copyWith(
                lastPosition: () => entry.position,
              );
              return MediaCard(
                item: item,
                autofocus: index == 0,
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.player, arguments: item),
                onRestart: () => Navigator.of(context).pushNamed(
                  AppRoutes.player,
                  arguments: item.copyWith(lastPosition: () => null),
                ),
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
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
            'Isso remove o registro de vídeos assistidos. Seus arquivos não serão apagados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await dependencies.historyService.clear();
    }
  }
}
