import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_install_screen.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';

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
          animation: addons,
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
            DpadFieldExit(
              controller: _nameController,
              child: TextField(
                controller: _nameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Ex.: Catálogo da comunidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DpadFieldExit(
              controller: _originController,
              child: TextField(
                controller: _originController,
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
            SwitchListTile(
              title: const Text('Confiável'),
              subtitle:
                  const Text('Marque somente origens que você reconhece.'),
              value: _trusted,
              onChanged:
                  _busy ? null : (value) => setState(() => _trusted = value),
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
            label: 'Tentar novamente',
            icon: Icons.refresh,
            primary: true,
            onPressed: () => _openRepo(repo),
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
            widget.dependencies.addonService.findById(manifest.id) != null;
        return _RepoEntryTile(
          manifest: manifest,
          installed: installed,
          autofocus: index == 0,
          onInstall: () => Navigator.of(context).pushNamed(
            AppRoutes.addonInstall,
            arguments: AddonInstallArgs(
              manifest: manifest,
              originTrusted: repo.trusted,
            ),
          ),
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
      setState(() => _browseError = error.code == 'addon.fetch-failed'
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
                size: 28,
              ),
              const SizedBox(width: 12),
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

/// Item publicado: nome, versao, autor e instalar (ou "Instalado").
class _RepoEntryTile extends StatelessWidget {
  const _RepoEntryTile({
    required this.manifest,
    required this.installed,
    required this.onInstall,
    this.autofocus = false,
  });

  final AddonManifest manifest;
  final bool installed;
  final VoidCallback onInstall;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            if (installed)
              Text('Instalado', style: theme.textTheme.bodyMedium)
            else
              FocusableButton(
                label: 'Instalar',
                icon: Icons.download,
                autofocus: autofocus,
                onPressed: onInstall,
              ),
          ],
        ),
      ),
    );
  }
}
