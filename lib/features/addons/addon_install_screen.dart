import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/focusable_button.dart';

/// Origem do manifesto na tela de instalacao.
enum AddonInstallSource { file, paste, link }

/// Argumentos da rota de instalacao: URL ja preenchida ou manifesto
/// ja obtido (fluxo de repositorios, spec 6.1). Ou um, ou outro.
class AddonInstallArgs {
  const AddonInstallArgs(
      {this.sourceUrl, this.manifest, this.originTrusted = false})
      : assert(sourceUrl == null || manifest == null);

  final String? sourceUrl;
  final AddonManifest? manifest;

  /// Confianca da origem, registrada na instalacao. Nao muda o padrao
  /// seguro (sempre instala desativado).
  final bool originTrusted;
}

/// Instalacao de add-on (spec 6.1): entrada por arquivo, texto colado
/// ou URL, seguida de REVISAO humana (detalhes, permissoes, aviso
/// legal) antes de confirmar. Instala sempre desativado. O botao
/// Cancelar da revisao aborta sem tocar no estado instalado.
class AddonInstallScreen extends StatefulWidget {
  const AddonInstallScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<AddonInstallScreen> createState() => _AddonInstallScreenState();
}

class _AddonInstallScreenState extends State<AddonInstallScreen> {
  static const _maxWidth = 520.0;

  AddonInstallSource _source = AddonInstallSource.file;
  bool _argsInitialized = false;
  final _fileController = TextEditingController();
  final _pasteController = TextEditingController();
  final _urlController = TextEditingController();
  SourcePreview? _preview;
  bool _originTrusted = false;
  bool _cameWithManifest = false;
  bool _approved = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AddonInstallArgs) {
        final withManifest = args.manifest;
        if (withManifest != null) {
          _preview = SourcePreview(
            manifest: withManifest,
            feedItemCount: null,
          );
          _originTrusted = args.originTrusted;
          _cameWithManifest = true;
        } else if (args.sourceUrl != null) {
          _source = AddonInstallSource.link;
          _urlController.text = args.sourceUrl!;
        }
      }
      _argsInitialized = true;
    }
  }

  @override
  void dispose() {
    _fileController.dispose();
    _pasteController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Instalar add-on',
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
                if (_preview == null) _inputStep() else _reviewStep(),
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

  Widget _inputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<AddonInstallSource>(
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.transparent),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
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
                value: AddonInstallSource.file,
                icon: Icon(Icons.folder_open),
                label: Text('Arquivo'),
              ),
              ButtonSegment(
                value: AddonInstallSource.paste,
                icon: Icon(Icons.content_paste),
                label: Text('Colar'),
              ),
              ButtonSegment(
                value: AddonInstallSource.link,
                icon: Icon(Icons.link),
                label: Text('Link'),
              ),
            ],
            selected: {_source},
            onSelectionChanged: _busy
                ? null
                : (selection) {
                    setState(() {
                      _source = selection.first;
                      _error = null;
                    });
                  },
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 28),
        switch (_source) {
          AddonInstallSource.file => _fileSection(),
          AddonInstallSource.paste => _pasteSection(),
          AddonInstallSource.link => _linkSection(),
        },
      ],
    );
  }

  Widget _fileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escolha um arquivo de manifesto (.json).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Procurar arquivo…',
          icon: Icons.folder_open,
          primary: true,
          onPressed: _busy ? null : _browseFile,
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
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Caminho do manifesto',
              hintText: r'C:\Add-ons\exemplo.json',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _readFile(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Ler arquivo',
          icon: Icons.description,
          onPressed: _busy ? null : _readFile,
        ),
      ],
    );
  }

  Widget _pasteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cole o conteúdo do manifesto (.json).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        DpadFieldExit(
          controller: _pasteController,
          child: TextField(
            controller: _pasteController,
            enabled: !_busy,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Manifesto JSON',
              hintText: '{"id": "…"}',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Continuar',
          icon: Icons.arrow_forward,
          primary: true,
          onPressed: _busy ? null : _readPaste,
        ),
      ],
    );
  }

  Widget _linkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Informe o endereço do manifesto ou do feed JSON (http/https).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        DpadFieldExit(
          controller: _urlController,
          child: TextField(
            controller: _urlController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'URL do manifesto ou feed',
              hintText: 'https://…',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _fetchLink(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Buscar fonte',
          icon: Icons.cloud_download,
          primary: true,
          onPressed: _busy ? null : _fetchLink,
        ),
      ],
    );
  }

  Widget _reviewStep() {
    final preview = _preview!;
    final manifest = preview.manifest;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revise antes de instalar',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        // Aviso de origem (spec 6.1.1): desconhecida nunca parece
        // verificada. Icone + texto, nunca so cor.
        if (!_originTrusted) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.help_outline,
                    size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fonte desconhecida — não verificada pelo aplicativo. '
                    'Revise os dados abaixo antes de aprovar.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          color: const Color(0xFF1C1C1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manifest.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'v${manifest.version} · ${manifest.author}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  manifest.description,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _ReviewRow(
                  title: 'Origem',
                  value: manifest.repository,
                ),
                _ReviewRow(
                  title: 'Conteúdo',
                  value: manifest.contentTypes.join(', '),
                ),
                _ReviewRow(
                  title: 'Plataformas',
                  value: manifest.supportedPlatforms.join(', '),
                ),
                _ReviewRow(
                  title: 'Permissões',
                  value: manifest.permissions.isEmpty
                      ? 'Nenhuma'
                      : manifest.permissions
                          .map(formatAddonPermission)
                          .join('\n'),
                ),
                if (preview.feedItemCount != null) ...[
                  const SizedBox(height: 8),
                  _ReviewRow(
                    title: 'Catálogo',
                    value: switch (preview.feedItemCount) {
                      0 => 'Feed vazio (0 itens)',
                      1 =>
                        '1 item:\n${preview.feedSample.join('\n')}',
                      final n =>
                        '$n itens:\n${preview.feedSample.join('\n')}',
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  manifest.legalNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline,
                size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Será instalado desativado. Ative nos detalhes após revisar.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Aprovacao explicita (spec 6.1.1): origem desconhecida so
        // instala com o aceite marcado. Confiavel instala direto.
        if (!_originTrusted)
          CheckboxListTile(
            title: const Text(
              'Entendo que esta fonte não foi verificada pelo aplicativo.',
            ),
            value: _approved,
            onChanged: _busy
                ? null
                : (value) => setState(() => _approved = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: FocusableButton(
                label: 'Cancelar',
                icon: Icons.close,
                onPressed: _busy ? null : _cancelReview,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FocusableButton(
                label: 'Instalar',
                icon: Icons.download,
                primary: true,
                onPressed:
                    (_busy || (!_originTrusted && !_approved))
                        ? null
                        : _confirmInstall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _browseFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Escolher manifesto',
    );
    final path = files.singleOrNull?.path;
    if (path == null || path.isEmpty) return;
    _fileController.text = path;
    await _readFile();
  }

  Future<void> _readFile() async {
    final path = _fileController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Informe o caminho do manifesto.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          setState(
              () => _error = 'Arquivo não encontrado. Verifique o caminho.');
        }
        return;
      }
      if (await file.length() > AppConstants.maxManifestBytes) {
        throw const AddonError.invalidManifest(
          'O manifesto é grande demais (limite de 256 KB).',
        );
      }
      _toReview(SourcePreview(
        manifest: AddonManifest.parseJson(await file.readAsString()),
        feedItemCount: null,
      ));
    } on AppError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível ler o arquivo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _readPaste() {
    final raw = _pasteController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Cole o conteúdo do manifesto.');
      return;
    }
    try {
      _toReview(SourcePreview(
        manifest: AddonManifest.parseJson(raw),
        feedItemCount: null,
      ));
    } on AddonError catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _fetchLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Informe o endereço da fonte.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview =
          await widget.dependencies.addonService.previewSource(url);
      if (mounted) _toReview(preview);
    } on AddonError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível buscar a fonte.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toReview(SourcePreview preview) {
    setState(() {
      _preview = preview;
      // Aceite sempre recomeça desmarcado: cada revisão aprova de novo.
      _approved = false;
      _error = null;
    });
  }

  void _cancelReview() {
    // Quem veio do repositorio volta para ele; quem digitou volta
    // para a entrada.
    if (_cameWithManifest) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _preview = null;
      _error = null;
    });
  }

  Future<void> _confirmInstall() async {
    final manifest = _preview?.manifest;
    if (manifest == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.dependencies.addonService
          .install(manifest, originTrusted: _originTrusted);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add-on instalado desativado.')),
      );
    } on AddonError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível instalar o add-on.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Linha titulo/valor da revisao (mesmo vocabulario dos detalhes).
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
