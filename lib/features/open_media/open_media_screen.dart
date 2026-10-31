import 'dart:async';

import 'package:flutter/material.dart';
import 'package:player/features/open_media/pick_video_file.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/thumbnail_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/focusable_button.dart';

/// Aba inicial da tela de abertura (arquivo ou link).
enum OpenMediaTab { file, link }

/// Argumentos da rota de abertura: aba inicial e valor ja preenchido
/// (usado por "Editar link" e fluxos de erro, spec 17).
class OpenMediaArgs {
  const OpenMediaArgs({required this.tab, this.initialValue});

  final OpenMediaTab tab;
  final String? initialValue;
}

/// Abertura de arquivo local e link (spec 9, 10), em coluna centralizada de
/// largura limitada como nos apps GNOME/Adwaita: o conteudo nunca estica
/// com a janela.
class OpenMediaScreen extends StatefulWidget {
  const OpenMediaScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<OpenMediaScreen> createState() => _OpenMediaScreenState();
}

class _OpenMediaScreenState extends State<OpenMediaScreen> {
  static const _maxWidth = 520.0;

  OpenMediaTab _tab = OpenMediaTab.file;
  bool _tabInitialized = false;
  final _fileController = TextEditingController();
  final _urlController = TextEditingController();
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tabInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is OpenMediaTab) {
        _tab = args;
      } else if (args is OpenMediaArgs) {
        _tab = args.tab;
        if (args.initialValue != null) {
          if (args.tab == OpenMediaTab.file) {
            _fileController.text = args.initialValue!;
          } else {
            _urlController.text = args.initialValue!;
          }
        }
      }
      _tabInitialized = true;
    }
  }

  @override
  void dispose() {
    _fileController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Abrir vídeo',
      showBack: true,
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<OpenMediaTab>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.transparent),
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? PlayerTheme.primaryText
                              : PlayerTheme.secondaryText),
                      side: const WidgetStatePropertyAll(
                        BorderSide(color: Color(0x1FFFFFFF)),
                      ),
                      shape: const WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: OpenMediaTab.file,
                        icon: Icon(Icons.folder_open),
                        label: Text('Arquivo'),
                      ),
                      ButtonSegment(
                        value: OpenMediaTab.link,
                        icon: Icon(Icons.link),
                        label: Text('Link'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _tab = selection.first;
                        _error = null;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 28),
                if (_tab == OpenMediaTab.file)
                  _fileSection()
                else
                  _linkSection(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escolha um arquivo de vídeo.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Procurar arquivo…',
          icon: Icons.folder_open,
          primary: true,
          autofocus: true,
          onPressed: _browseFile,
        ),
        const SizedBox(height: 20),
        Text(
          'Ou informe o caminho diretamente:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        DpadFieldExit(
          controller: _fileController,
          child: TextField(
            controller: _fileController,
            decoration: const InputDecoration(
              labelText: 'Caminho do arquivo',
              hintText: r'C:\Vídeos\exemplo.mp4',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _openFile(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Abrir arquivo',
          icon: Icons.play_arrow,
          onPressed: _openFile,
        ),
      ],
    );
  }

  Widget _linkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cole um link de mídia autorizado (http/https).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        DpadFieldExit(
          controller: _urlController,
          child: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL do vídeo',
              hintText: 'https://…',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _openLink(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Carregar link',
          icon: Icons.play_arrow,
          primary: true,
          autofocus: true,
          onPressed: _openLink,
        ),
      ],
    );
  }

  /// Seletor nativo de arquivos (Fase 2). O caminho digitado continua
  /// disponivel como alternativa e e o que os testes exercitam.
  Future<void> _browseFile() async {
    final path = await pickVideoFile(context, title: 'Escolher vídeo');
    if (!mounted) return;
    if (path == null || path.isEmpty) return;
    _fileController.text = path;
    await _openFile();
  }

  Future<void> _openFile() async {
    final path = _fileController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Informe o caminho do arquivo.');
      return;
    }
    final item = MediaItem(
      id: _newId(),
      title: titleFromSource(path),
      sourceType: MediaSourceType.local,
      source: path,
      addedAt: DateTime.now(),
    );
    await _play(item);
  }

  Future<void> _openLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = const ValidationError.emptyUrl().message);
      return;
    }
    if (!isSupportedUrl(url)) {
      setState(() => _error = const ValidationError.malformedUrl().message);
      return;
    }
    final item = MediaItem(
      id: _newId(),
      title: titleFromSource(url),
      sourceType: MediaSourceType.url,
      source: url,
      addedAt: DateTime.now(),
    );
    await _play(item);
  }

  Future<void> _play(MediaItem item) async {
    setState(() => _error = null);
    final library = widget.dependencies.libraryService;
    final saved = await library.upsert(item);
    // Miniatura em segundo plano (spec 15.1). Não depende de mounted:
    // esta rota é substituída pelo player.
    unawaited(ThumbnailService.backfill(library, saved));
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacementNamed(AppRoutes.player, arguments: saved);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
