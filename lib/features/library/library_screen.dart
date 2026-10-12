import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';

/// Biblioteca local (spec 15.1): itens adicionados pelo usuario.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    return AppShell(
      title: 'Biblioteca',
      showBack: true,
      body: AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final items = library.items;
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Biblioteca vazia',
              message:
                  'Ainda não há vídeos aqui. Abra um arquivo ou um link para começar.',
              actions: [
                FocusableButton(
                  label: 'Abrir vídeo',
                  icon: Icons.add,
                  primary: true,
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.openMedia,
                    arguments: const OpenMediaArgs(tab: OpenMediaTab.file),
                  ),
                ),
              ],
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
                onToggleFavorite: () => library.toggleFavorite(item.id),
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
