import 'package:flutter/material.dart';

import 'package:player/services/media_permission_service.dart';
import 'package:player/services/video_file_listing.dart';
import 'package:player/widgets/focusable_button.dart';

/// Navegador de vídeos para a TV, com controle remoto (D-pad). Existe porque
/// o seletor do sistema não abre no Google TV (o stub some na hora). OK numa
/// pasta entra nela; OK num vídeo devolve o caminho; Voltar sobe uma pasta e,
/// na raiz, fecha sem escolher.
class TvFileBrowserScreen extends StatefulWidget {
  const TvFileBrowserScreen({
    super.key,
    this.roots = tvBrowseRoots,
    this.list = listVideoFolder,
    this.ensureAccess,
  });

  /// Pastas de partida (só as que existem aparecem).
  final List<String> roots;

  /// Listagem injetável (testes); o padrão lê o armazenamento.
  final Future<List<BrowserEntry>> Function(String path) list;

  /// Pede acesso aos arquivos (padrão: permissão do Android).
  final Future<bool> Function()? ensureAccess;

  @override
  State<TvFileBrowserScreen> createState() => _TvFileBrowserScreenState();
}

class _TvFileBrowserScreenState extends State<TvFileBrowserScreen> {
  /// Pasta atual; null = raiz (as pastas de partida).
  String? _folder;
  List<BrowserEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Sem permissão o listing volta vazio; a tela explica abaixo.
    final grant =
        widget.ensureAccess ?? const MediaPermissionService().ensureAccess;
    await grant();
    final entries = _folder == null
        ? [
            for (final root in widget.roots)
              BrowserEntry(
                name: root.split('/').last,
                path: root,
                isDirectory: true,
              ),
          ]
        : await widget.list(_folder!);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _open(BrowserEntry entry) {
    if (!entry.isDirectory) {
      Navigator.of(context).pop(entry.path);
      return;
    }
    _folder = entry.path;
    _load();
  }

  /// Voltar: sobe uma pasta; na raiz, fecha sem escolher.
  void _up() {
    final folder = _folder;
    if (folder == null) {
      Navigator.of(context).pop();
      return;
    }
    final parent = folder.substring(0, folder.lastIndexOf('/'));
    final isRoot = widget.roots.contains(folder);
    _folder = isRoot || parent.isEmpty ? null : parent;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _folder == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_folder ?? 'Escolher vídeo'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _up,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhum vídeo nesta pasta. Conceda acesso aos arquivos '
                        'ou escolha outra pasta.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return FocusableButton(
                        label:
                            entry.isDirectory ? '${entry.name}/' : entry.name,
                        icon: entry.isDirectory
                            ? Icons.folder_outlined
                            : Icons.movie_outlined,
                        autofocus: index == 0,
                        onPressed: () => _open(entry),
                      );
                    },
                  ),
      ),
    );
  }
}
