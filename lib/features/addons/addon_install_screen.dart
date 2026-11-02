import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/features/addons/pick_addon_file.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/app_toast.dart';
import 'package:player/services/addon_package.dart';
import 'package:player/widgets/confirm_dialog.dart';

/// Origem do manifesto na tela de instalacao.
enum AddonInstallSource { file, paste, link, zip }

/// Argumentos da rota de instalacao: URL ja preenchida ou manifesto
/// ja obtido (fluxo de repositorios, spec 6.1). Ou um, ou outro.
class AddonInstallArgs {
  const AddonInstallArgs(
      {this.sourceUrl,
      this.manifest,
      this.originTrusted = false,
      this.source})
      : assert(sourceUrl == null || manifest == null);

  /// Aba inicial da entrada ("Instalar de zip" abre direto no Zip).
  final AddonInstallSource? source;

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
  final _zipPathController = TextEditingController();
  final _zipUrlController = TextEditingController();
  SourcePreview? _preview;
  bool _originTrusted = false;
  bool _cameWithManifest = false;
  bool _approved = false;
  bool _busy = false;
  String? _error;
  AddonPackage? _package;
  String? _packageSha256;
  bool _downloading = false;
  int _downloadReceived = 0;
  int? _downloadTotal;
  Completer<void>? _downloadCancel;
  bool _retryDownload = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AddonInstallArgs) {
        _source = args.source ?? _source;
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
    final pending = _downloadCancel;
    if (pending != null && !pending.isCompleted) pending.complete();
    _fileController.dispose();
    _pasteController.dispose();
    _urlController.dispose();
    _zipPathController.dispose();
    _zipUrlController.dispose();
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
                AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.dependencies.preferencesService,
                    widget.dependencies.addonService,
                  ]),
                  builder: (context, _) {
                    if (_preview == null &&
                        !widget.dependencies.addonService
                            .unknownSourcesAllowed) {
                      return _blockedPanel();
                    }
                    if (_preview == null) return _inputStep();
                    return _reviewStep();
                  },
                ),
                if (_error != null && !_blockedByGate) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  if (_retryDownload && !_busy) ...[
                    const SizedBox(height: 12),
                    FocusableButton(
                      label: 'Tentar de novo',
                      icon: Icons.refresh,
                      onPressed: _downloadZip,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A recusa do botão desligado mostra o atalho para ligar junto do
  /// motivo (T1). Compara a mensagem fixa do erro, sem tocar nos
  /// outros caminhos de erro da tela.
  bool get _blockedByGate => AddonError.isUnknownSourcesBlock(_error);

  /// Entrada bloqueada: motivo + atalho para ligar (T1). A revisão de
  /// origem confiável não passa por aqui.
  Widget _blockedPanel() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Instalação bloqueada',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Fontes desconhecidas estão desligadas, e este aparelho não '
          'aceita origens novas. Ative para instalar por arquivo, texto '
          'ou link.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FocusableButton(
          label: 'Ativar fontes desconhecidas',
          icon: Icons.lock_open,
          primary: true,
          autofocus: true,
          onPressed: _enableUnknownSources,
        ),
      ],
    );
  }

  Future<void> _enableUnknownSources() async {
    final confirmed = await confirmEnableUnknownSources(context);
    if (!confirmed || !mounted) return;
    await widget.dependencies.preferencesService.update(
      widget.dependencies.preferencesService.current
          .copyWith(allowUnknownSources: true),
    );
    if (mounted) setState(() => _error = null);
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
            segments: [
              for (final (value, icon, label) in const [
                (AddonInstallSource.file, Icons.folder_open, 'Arquivo'),
                (AddonInstallSource.paste, Icons.content_paste, 'Colar'),
                (AddonInstallSource.link, Icons.link, 'Link'),
                (AddonInstallSource.zip, Icons.folder_zip, 'Zip'),
              ])
                ButtonSegment(
                  value: value,
                  // Em 360 dp, ícone e nome não cabem: "Arquivo" quebrava.
                  icon: MobileMode.of(context) ? null : Icon(icon),
                  label: Text(label),
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
          AddonInstallSource.zip => _zipSection(),
        },
      ],
    );
  }

  Widget _zipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escolha um pacote (.zip) do aparelho.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Procurar pacote…',
          icon: Icons.folder_zip,
          primary: true,
          // Depois de ativar as fontes o botão de antes some: sem foco aqui,
          // a primeira seta da TV caía em "Voltar".
          autofocus: true,
          onPressed: _busy ? null : _browseZip,
        ),
        const SizedBox(height: 20),
        Text(
          'Ou informe o caminho diretamente:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        DpadFieldExit(
          controller: _zipPathController,
          child: TextField(
            controller: _zipPathController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Caminho do pacote',
              hintText: r'/armazenamento/pacote.zip',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _readZip(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Ler pacote',
          icon: Icons.folder_zip,
          onPressed: _busy ? null : _readZip,
        ),
        const SizedBox(height: 20),
        Text(
          'Ou cole o link do pacote (.zip):',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        DpadFieldExit(
          controller: _zipUrlController,
          child: TextField(
            controller: _zipUrlController,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link do pacote',
              hintText: 'https://…/pacote.zip',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _downloadZip(),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          label: 'Baixar pacote',
          icon: Icons.cloud_download,
          onPressed: _busy ? null : _downloadZip,
        ),
        if (_downloading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            key: const Key('downloadProgress'),
            value: _downloadTotal != null && _downloadTotal! > 0
                ? (_downloadReceived / _downloadTotal!).clamp(0.0, 1.0)
                : null,
          ),
          const SizedBox(height: 8),
          Text(_downloadLabel, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FocusableButton(
            label: 'Cancelar download',
            icon: Icons.close,
            onPressed: _cancelDownload,
          ),
        ],
      ],
    );
  }

  /// Rótulo do progresso: porcentagem com total, KB sem total.
  String get _downloadLabel {
    if (_downloadTotal != null && _downloadTotal! > 0) {
      final pct =
          (100 * _downloadReceived / _downloadTotal!).clamp(0, 100).round();
      return 'Baixando… $pct%';
    }
    return 'Baixando… ${(_downloadReceived / 1024).round()} KB';
  }

  Future<void> _browseZip() async {
    final path = await pickAddonFile(
      context,
      extension: 'zip',
      title: 'Escolher pacote',
    );
    if (path == null || path.isEmpty || !mounted) return;
    _zipPathController.text = path;
    await _readZip();
  }

  Future<void> _readZip() async {
    final path = _zipPathController.text.trim();
    if (path.isEmpty) {
      setState(() {
        _error = 'Informe o caminho do pacote.';
        _retryDownload = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _retryDownload = false;
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
      // Teto pelo tamanho no disco, antes de carregar na memória.
      if (await file.length() > AddonPackageLimits.maxCompressedBytes) {
        throw const AddonError.invalidManifest(
          'O pacote é grande demais (limite de 10 MB).',
        );
      }
      final bytes = await file.readAsBytes();
      final package =
          await widget.dependencies.addonService.previewPackage(bytes);
      if (!mounted) return;
      _toPackageReview(package);
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

  /// Revisão de pacote (arquivo ou link): mesmos dados, mesma tela.
  void _toPackageReview(AddonPackage package) {
    setState(() {
      _package = package;
      _packageSha256 = package.sha256;
      _preview = SourcePreview(
        manifest: package.manifest,
        feedItemCount: package.catalogItemCount,
        feedSample: package.catalogSample,
      );
      _originTrusted = false;
      _error = null;
      _retryDownload = false;
    });
  }

  /// Baixa o zip do link com progresso e cancelamento (T3) e cai
  /// na mesma revisão do arquivo. Sem temporário por construção.
  Future<void> _downloadZip() async {
    final url = _zipUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _error = 'Informe o link do pacote.';
        _retryDownload = false;
      });
      return;
    }
    final cancel = Completer<void>();
    setState(() {
      _busy = true;
      _downloading = true;
      _downloadReceived = 0;
      _downloadTotal = null;
      _error = null;
      _retryDownload = false;
      _downloadCancel = cancel;
    });
    try {
      final package = await widget.dependencies.addonService
          .previewPackageFromLink(
        url,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadReceived = received;
              _downloadTotal = total;
            });
          }
        },
        cancel: cancel.future,
      );
      if (!mounted) return;
      _toPackageReview(package);
    } on AppError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _retryDownload = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível baixar o pacote.';
          _retryDownload = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloading = false;
        });
      }
    }
  }

  void _cancelDownload() {
    final cancel = _downloadCancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
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
    if (_blockedByGate) return _blockedPanel();
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
                // Pacote do repositorio (T4): mostra o checksum
                // anunciado, conferido contra o baixado na instalacao.
                if (_packageSha256 != null ||
                    manifest.packageSha256 != null)
                  _ReviewRow(
                    title: 'SHA-256',
                    value: _packageSha256 ?? manifest.packageSha256!,
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
          if (_downloading) ...[
            LinearProgressIndicator(
              key: const Key('downloadProgress'),
              value: _downloadTotal != null && _downloadTotal! > 0
                  ? (_downloadReceived / _downloadTotal!).clamp(0.0, 1.0)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(_downloadLabel, textAlign: TextAlign.center),
          ] else ...[
            const LinearProgressIndicator(),
          ],
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
    final path = await pickAddonFile(
      context,
      extension: 'json',
      title: 'Escolher manifesto',
    );
    if (path == null || path.isEmpty || !mounted) return;
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
      _package = null;
      _packageSha256 = null;
      _error = null;
    });
  }

  Future<void> _confirmInstall() async {
    final manifest = _preview?.manifest;
    if (manifest == null) return;
    setState(() {
      _busy = true;
      _downloading = manifest.packageUrl != null && _package == null;
      _downloadReceived = 0;
      _downloadTotal = null;
      _error = null;
    });
    try {
      if (_package != null) {
        await widget.dependencies.addonService.installPackage(
          _package!,
          originTrusted: _originTrusted,
        );
      } else if (manifest.packageUrl != null) {
        // Pacote do repositorio (T4): baixa com progresso e instala
        // com checksum, id e versao conferidos no servico.
        await widget.dependencies.addonService.installPackageFromRepo(
          manifest,
          originTrusted: _originTrusted,
          onProgress: (received, total) {
            if (mounted) {
              setState(() {
                _downloadReceived = received;
                _downloadTotal = total;
              });
            }
          },
        );
      } else {
        await widget.dependencies.addonService
            .install(manifest, originTrusted: _originTrusted);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppToast(context, 'Add-on instalado desativado.');
    } on AddonError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível instalar o add-on.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloading = false;
        });
      }
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
