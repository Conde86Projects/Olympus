import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/features/library/library_view.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/media_card.dart';

/// Biblioteca local (spec 15.1): itens adicionados pelo usuario, com busca
/// por titulo e ordem lembrada. Busca e ordem nao mudam o que fica salvo.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _query = TextEditingController();
  final _field = FocusNode();

  /// Na TV o campo so abre o teclado depois do OK: sem isso, passar por
  /// ele com as setas (para chegar ao botao de voltar) abria o teclado.
  bool _typing = false;

  static const _sortLabels = {
    LibrarySort.recent: 'Recentes',
    LibrarySort.title: 'Título',
    LibrarySort.duration: 'Duração',
  };

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _field.addListener(() {
      if (!_field.hasFocus && _typing) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  /// Teclas do controle no campo da TV enquanto ele espera o OK: OK comeca
  /// a digitar; esquerda e direita saem do campo (senao ele as engole para
  /// mover o cursor e prende o foco antes do seletor de ordem).
  KeyEventResult _onTvKey(FocusNode node, KeyEvent event) {
    if (_typing || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      setState(() => _typing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _field.context?.findAncestorStateOfType<EditableTextState>()
            ?.requestKeyboard();
      });
      return KeyEventResult.handled;
    }
    final side = switch (key) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (side == null) return KeyEventResult.ignored;
    return node.focusInDirection(side)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _setSort(LibrarySort sort) {
    final preferences = widget.dependencies.preferencesService;
    preferences.update(preferences.current.copyWith(librarySort: sort));
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.dependencies.libraryService;
    final preferences = widget.dependencies.preferencesService;
    return AppShell(
      title: 'Biblioteca',
      showBack: true,
      body: AnimatedBuilder(
        animation: Listenable.merge([library, preferences]),
        builder: (context, _) {
          final all = library.items;
          if (all.isEmpty) return _emptyLibrary(context);
          final sort = preferences.current.librarySort;
          final items = libraryView(all, query: _query.text, sort: sort);
          return Column(
            children: [
              _toolbar(context, sort),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty ? _noResults() : _list(context, items),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyLibrary(BuildContext context) {
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

  Widget _toolbar(BuildContext context, LibrarySort sort) {
    final tv = TvMode.of(context);
    final idle = tv && !_typing;
    return Row(
      children: [
        Expanded(
          child: Focus(
            skipTraversal: true,
            onKeyEvent: tv ? _onTvKey : null,
            child: DpadFieldExit(
              controller: _query,
              child: TextField(
                controller: _query,
                focusNode: _field,
                readOnly: idle,
                textInputAction: TextInputAction.search,
                // Buscar: leva o foco para a lista e fecha o teclado. Com
                // este gancho o campo nao se desfaz do foco antes de mover.
                onEditingComplete: () =>
                    _field.focusInDirection(TraversalDirection.down),
                decoration: InputDecoration(
                  hintText:
                      idle ? 'Buscar pelo título (OK para digitar)' : 'Buscar pelo título',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<LibrarySort>(
          value: sort,
          items: [
            for (final entry in _sortLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) {
            if (value != null) _setSort(value);
          },
        ),
      ],
    );
  }

  /// Busca sem resultado. Sem foco automatico: ele tiraria o cursor do
  /// campo enquanto a pessoa ainda digita.
  Widget _noResults() {
    return EmptyState(
      icon: Icons.search_off,
      title: 'Nada encontrado',
      message: 'Nenhum vídeo da biblioteca tem este texto no título.',
      actions: [
        FocusableButton(
          label: 'Limpar busca',
          icon: Icons.clear,
          onPressed: _query.clear,
        ),
      ],
    );
  }

  Widget _list(BuildContext context, List<MediaItem> items) {
    final library = widget.dependencies.libraryService;
    final history = widget.dependencies.historyService;
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
  }
}
