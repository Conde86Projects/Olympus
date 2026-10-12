import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';

/// Favoritos (spec 15.2): adicionar, remover, filtrar e reproduzir.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    return AppShell(
      title: 'Favoritos',
      showBack: true,
      body: AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final items = library.favorites;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_outline,
              title: 'Sem favoritos',
              message:
                  'Marque um vídeo como favorito para encontrá-lo aqui.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return MediaCard(
                item: item,
                autofocus: index == 0,
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.player, arguments: item),
                onToggleFavorite: () =>
                    library.toggleFavorite(item.id),
                onRemove: () async {
                  // F3 (Fase 4b): confirma; cascata o histórico como o
                  // player (sem órfãos invisíveis).
                  final confirmed = await confirmDestructiveAction(
                    context,
                    title: 'Remover da biblioteca?',
                    message:
                        "'${item.title}' sai da biblioteca e do histórico. O arquivo original não é apagado.",
                  );
                  if (!confirmed) return;
                  await library.remove(item.id);
                  await history.remove(item.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}
