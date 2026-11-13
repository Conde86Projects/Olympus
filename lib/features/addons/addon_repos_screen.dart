import 'package:flutter/material.dart';
import 'package:player/widgets/app_switch_theme.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_install_screen.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/tv_text_field_frame.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/confirm_dialog.dart';

/// Repositorios autorizados (spec 6.1): cadastro com validacao de
/// endereco, marca de confianca e navegacao do conteudo. Instalar um
/// item cai no fluxo de revisao da instalacao. Repositorio fora do ar
/// mostra "fonte indisponivel" com nova tentativa, sem travar.
class AddonReposScreen extends StatefulWidget {
  const AddonReposScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<AddonReposScreen> createState() => _AddonReposScreenState();
}

class _AddonReposScreenState extends State<AddonReposScreen> {
  final _nameController = TextEditingController();
  final _originController = TextEditingController();
  final _nameFocus = FocusNode();
  final _originFocus = FocusNode();
  bool _trusted = false;
  String? _selectedId;
  List<AddonManifest>? _listing;
  bool _busy = false;
  String? _error;
  String? _browseError;

  @override
  void dispose() {
    _nameController.dispose();
    _originController.dispose();
    _nameFocus.dispose();
    _originFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final addons = widget.dependencies.addonService;
    AddonRepository? lookup(String? id) {
      if (id == null) return null;
      for (final repo in addons.repositories) {
        if (repo.id == id) return repo;
      }
      return null;
    }

    return PopScope(
      canPop: _selectedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _selectedId = null;
          _listing = null;
          _browseError = null;
        });
      },
      child: AppShell(
        title: lookup(_selectedId)?.name ?? 'Repositórios',
        showBack: true,
        body: AnimatedBuilder(
          animation: Listenable.merge(
              [addons, widget.dependencies.preferencesService]),
          builder: (context, _) {
            final repo = lookup(_selectedId);
            if (repo == null) return _listStep(addons.repositories);
            return _browseStep(repo);
          },
        ),
      ),
    );
  }

  Widget _listStep(List<AddonRepository> repos) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _addForm(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (repos.isEmpty)
            const EmptyState(
              icon: Icons.storage_outlined,
              title: 'Nenhum repositório cadastrado',
              message: 'Cadastre um endereço acima para navegar nos '
                  'add-ons publicados por ele.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: repos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final repo = repos[index];
                return _RepoTile(
                  repo: repo,
                  autofocus: index == 0,
                  onTap: () => _openRepo(repo),
                  onRemove: () => _confirmRemove(repo),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _addForm() {
    if (!widget.dependencies.addonService.unknownSourcesAllowed) {
      return _blockedCard();
    }
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adicionar repositório', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TvTextFieldFrame(
              controller: _nameController,
              fieldFocus: _nameFocus,
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Ex.: Catálogo da comunidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TvTextFieldFrame(
              controller: _originController,
              fieldFocus: _originFocus,
              child: TextField(
                controller: _originController,
                focusNode: _originFocus,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Endereço da listagem',
                  hintText: 'https://…',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _addRepo(),
              ),
            ),
            AppSwitchTheme(
              child: SwitchListTile(
                title: const Text('Confiável'),
                subtitle:
                    const Text('Marque somente origens que você reconhece. '
                        'Só repositório confiável pode estar na sua rede local.'),
                value: _trusted,
                onChanged:
                    _busy ? null : (value) => setState(() => _trusted = value),
              ),
            ),
            const SizedBox(height: 8),
            FocusableButton(
              label: 'Adicionar',
              icon: Icons.add,
              primary: true,
              onPressed: _busy ? null : _addRepo,
            ),
          ],
        ),
      ),
    );
  }

  /// A recusa do botão desligado mostra o atalho para ligar junto do
  /// motivo (T1). Compara a mensagem fixa do erro, sem tocar nos
  /// outros caminhos de erro da tela.
  bool get _browseBlockedByGate =>
      AddonError.isUnknownSourcesBlock(_browseError);

  /// Cadastro bloqueado: motivo + atalho para ligar (T1). A lista e a
  /// navegação em repositórios confiáveis seguem funcionando.
  Widget _blockedCard() {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cadastro bloqueado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'Fontes desconhecidas estão desligadas, e este aparelho não '
              'aceita origens novas. Ative para cadastrar repositórios.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FocusableButton(
              label: 'Ativar fontes desconhecidas',
              icon: Icons.lock_open,
              primary: true,
              onPressed: _enableUnknownSources,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableUnknownSources() async {
    final confirmed = await confirmEnableUnknownSources(context);
    if (!confirmed || !mounted) return;
    await widget.dependencies.preferencesService.update(
      widget.dependencies.preferencesService.current
          .copyWith(allowUnknownSources: true),
    );
    if (mounted) setState(() {});
  }

  Future<void> _enableAndRetry(AddonRepository repo) async {
    await _enableUnknownSources();
    if (!mounted) return;
    if (!widget.dependencies.preferencesService.current.allowUnknownSources) {
      return;
    }
    await _openRepo(repo);
  }

  Widget _browseStep(AddonRepository repo) {
    final theme = Theme.of(context);
    if (_busy) {
      return const Column(
        children: [
          SizedBox(height: 32),
          LinearProgressIndicator(),
        ],
      );
    }
    if (_browseError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text(
            _browseError!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FocusableButton(
            label: _browseBlockedByGate
                ? 'Ativar fontes desconhecidas'
                : 'Tentar novamente',
            icon: _browseBlockedByGate ? Icons.lock_open : Icons.refresh,
            primary: true,
            onPressed: () => _browseBlockedByGate
                ? _enableAndRetry(repo)
                : _openRepo(repo),
          ),
        ],
      );
    }
    final listing = _listing ?? const <AddonManifest>[];
    if (listing.isEmpty) {
      return const EmptyState(
        icon: Icons.extension_outlined,
        title: 'Nenhum add-on publicado',
        message: 'Este repositório não publicou add-ons.',
      );
    }
    return ListView.separated(
      itemCount: listing.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final manifest = listing[index];
        final installed =
            widget.dependencies.addonService.findById(manifest.id);
        final state = resolveRepoEntryState(
          manifest: manifest,
          installedVersion: installed?.manifest.version,
          platform: widget.dependencies.addonService.platform,
        );
        return _RepoEntryTile(
          manifest: manifest,
          state: state,
          autofocus: index == 0,
          onInstall: state == RepoEntryState.available
              ? () => Navigator.of(context).pushNamed(
                    AppRoutes.addonInstall,
                    arguments: AddonInstallArgs(
                      manifest: manifest,
                      originTrusted: repo.trusted,
                    ),
                  )
              : null,
        );
      },
    );
  }

  Future<void> _addRepo() async {
    setState(() => _error = null);
    try {
      await widget.dependencies.addonService.addRepository(
        name: _nameController.text,
        originUrl: _originController.text,
        trusted: _trusted,
      );
      if (!mounted) return;
      setState(() {
        _nameController.clear();
        _originController.clear();
        _trusted = false;
      });
    } on AddonError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível adicionar.');
      }
    }
  }

  Future<void> _openRepo(AddonRepository repo) async {
    setState(() {
      _selectedId = repo.id;
      _listing = null;
      _browseError = null;
      _busy = true;
    });
    try {
      final listing =
          await widget.dependencies.addonService.fetchRepoAddons(repo.id);
      if (mounted) setState(() => _listing = listing);
    } on AddonError catch (error) {
      if (!mounted) return;
      // Fora do ar vira "fonte indisponivel" (spec 17); listagem
      // malformada mostra o motivo da validacao.
      final local = error.message.contains('interno') && !repo.trusted;
      setState(() => _browseError = local
          ? 'Este endereço é da rede local. Remova o repositório e '
              'cadastre de novo marcando "Confiável".'
          : error.code == 'addon.fetch-failed'
              ? const AddonError.unavailable().message
              : error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _browseError = const AddonError.unavailable().message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(AddonRepository repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover repositório?'),
        content: const Text('Remove o cadastro. Add-ons instalados e '
            'mídias não são afetados.'),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6).
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.dependencies.addonService.removeRepository(repo.id);
    } on AddonError catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }
}

/// Linha de um repositorio: nome, origem, confianca (icone + texto) e
/// remocao com confirmacao. Focavel por teclado/controle (spec 18).
class _RepoTile extends StatelessWidget {
  const _RepoTile({
    required this.repo,
    required this.onTap,
    required this.onRemove,
    this.autofocus = false,
  });

  final AddonRepository repo;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = Uri.tryParse(repo.originUrl)?.host ?? '';
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
                repo.trusted ? Icons.verified_outlined : Icons.help_outline,
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
                      repo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host.isEmpty ? repo.originUrl : host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      repo.trusted ? 'Confiável' : 'Não verificado',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remover repositório',
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

/// Item publicado (T4): nome, versao, autor e o estado em icone +
/// texto (Instalado, Atualizacao disponivel, Nao compativel ou
/// Disponivel). So o disponivel oferece o botao instalar.
class _RepoEntryTile extends StatelessWidget {
  const _RepoEntryTile({
    required this.manifest,
    required this.state,
    this.onInstall,
    this.autofocus = false,
  });

  final AddonManifest manifest;
  final RepoEntryState state;
  final VoidCallback? onInstall;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (state) {
      RepoEntryState.installed =>
        (Icons.check_circle, 'Instalado'),
      RepoEntryState.updateAvailable =>
        (Icons.system_update, 'Atualização disponível'),
      RepoEntryState.incompatible => (Icons.block, 'Não compatível'),
      RepoEntryState.available =>
        (Icons.extension_outlined, 'Disponível'),
    };
    final stateStyle = state == RepoEntryState.incompatible
        ? theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error)
        : theme.textTheme.bodyMedium;
    final stateIconColor = state == RepoEntryState.incompatible
        ? theme.colorScheme.error
        : null;
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manifest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v${manifest.version} · ${manifest.author}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: stateIconColor),
                    const SizedBox(width: 6),
                    Text(label, style: stateStyle),
                  ],
                ),
                if (state == RepoEntryState.available &&
                    onInstall != null) ...[
                  const SizedBox(height: 8),
                  FocusableButton(
                    label: 'Instalar',
                    icon: Icons.download,
                    autofocus: autofocus,
                    onPressed: onInstall,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
