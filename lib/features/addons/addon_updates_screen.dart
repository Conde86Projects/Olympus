import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';

/// Atualizacoes controladas de add-ons (Task 10): verifica os updateUrls
/// ao abrir, mostra versao atual/nova + changelog + plataformas e oferece
/// atualizar (com confirmacao), adiar e voltar a versao anterior.
/// Nada e aplicado em silencio.
class AddonUpdatesScreen extends StatefulWidget {
  const AddonUpdatesScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<AddonUpdatesScreen> createState() => _AddonUpdatesScreenState();
}

class _AddonUpdatesScreenState extends State<AddonUpdatesScreen> {
  /// Manifestos mais novos do ultimo check, por id do add-on.
  final Map<String, AddonManifest> _pending = {};
  bool _checking = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final found =
          await widget.dependencies.addonService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _pending
          ..clear()
          ..addEntries(found.map((m) => MapEntry(m.id, m)));
        _checking = false;
      });
    } catch (_) {
      // O contrato promete que o check nunca lanca; isto e um cinto de
      // seguranca para nunca travar a tela em "verificando".
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Não foi possível verificar agora. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Atualizações',
      showBack: true,
      actions: [
        IconButton(
          tooltip: 'Verificar novamente',
          icon: const Icon(Icons.refresh),
          onPressed: (_checking || _busy) ? null : _refresh,
        ),
      ],
      body: AnimatedBuilder(
        animation: widget.dependencies.addonService,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final addons = widget.dependencies.addonService;
    final items = <({AddonInfo info, AddonManifest next})>[];
    for (final entry in _pending.entries) {
      final info = addons.findById(entry.key);
      // Ignora o que foi removido depois do check.
      if (info != null) items.add((info: info, next: entry.value));
    }
    final rollbacks = <({AddonInfo info, String previous})>[];
    for (final info in addons.addons) {
      final previous = addons.previousVersion(info.manifest.id);
      if (previous != null) {
        rollbacks.add((info: info, previous: previous));
      }
    }
    // O banner vive fora da ramificacao de conteudo: uma acao pode
    // esvaziar a lista (ex. rollback apos update) sem engolir a
    // confirmacao.
    return Column(
      children: [
        if (_error != null)
          _Banner(text: _error!, error: true)
        else if (_notice != null)
          _Banner(text: _notice!, error: false),
        Expanded(child: _content(items, rollbacks)),
      ],
    );
  }

  Widget _content(
    List<({AddonInfo info, AddonManifest next})> items,
    List<({AddonInfo info, String previous})> rollbacks,
  ) {
    if (_checking && items.isEmpty && rollbacks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verificando atualizações…'),
          ],
        ),
      );
    }
    if (items.isEmpty && rollbacks.isEmpty) {
      return EmptyState(
        icon: Icons.system_update,
        title: 'Tudo atualizado',
        message: 'Nenhum add-on tem atualização pendente.',
        actions: [
          FocusableButton(
            label: 'Verificar novamente',
            icon: Icons.refresh,
            autofocus: true,
            onPressed: _refresh,
          ),
        ],
      );
    }
    return ListView(
      children: [
        if (items.isNotEmpty) ...[
          _SectionTitle('Disponíveis (${items.length})'),
          for (var i = 0; i < items.length; i++)
            _UpdateCard(
              info: items[i].info,
              next: items[i].next,
              busy: _busy,
              autofocus: i == 0,
              onUpdate: () => _confirmUpdate(items[i].info, items[i].next),
              onDefer: () => _defer(items[i].info),
            ),
        ],
        if (rollbacks.isNotEmpty) ...[
          const _SectionTitle('Versão anterior guardada'),
          for (final entry in rollbacks)
            _RollbackTile(
              info: entry.info,
              previous: entry.previous,
              busy: _busy,
              onRollback: () => _confirmRollback(
                entry.info,
                entry.previous,
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmUpdate(AddonInfo info, AddonManifest next) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atualizar add-on?'),
        content: Text(
          '${info.manifest.name}\n'
          'v${info.manifest.version} → v${next.version}\n'
          'Plataformas: ${next.supportedPlatforms.join(', ')}\n\n'
          '${next.changelog ?? 'Sem notas desta versão.'}',
        ),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6).
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) await _applyUpdate(info, next);
  }

  Future<void> _applyUpdate(AddonInfo info, AddonManifest next) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.dependencies.addonService.update(info.manifest.id);
      if (!mounted) return;
      setState(() {
        _pending.remove(info.manifest.id);
        _notice =
            '${info.manifest.name} atualizado para v${next.version}.';
      });
    } on AppError catch (e) {
      // Incompativel, rede ou manifesto: motivo legivel, sem excecao.
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível atualizar agora.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _defer(AddonInfo info) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.dependencies.addonService.deferUpdate(info.manifest.id);
      if (!mounted) return;
      setState(() => _pending.remove(info.manifest.id));
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível adiar agora.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRollback(AddonInfo info, String previous) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voltar à versão anterior?'),
        content: Text(
          '${info.manifest.name}\n'
          'v${info.manifest.version} → v$previous\n\n'
          'A versão atual será descartada.',
        ),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6).
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Voltar versão'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      await _applyRollback(info, previous);
    }
  }

  Future<void> _applyRollback(AddonInfo info, String previous) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.dependencies.addonService.rollback(info.manifest.id);
      if (!mounted) return;
      setState(() {
        _notice = '${info.manifest.name} voltou para v$previous.';
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível voltar agora.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Theme.of(context).colorScheme.error : Colors.green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// Cartao de uma atualizacao pendente: antes/depois, plataformas,
/// changelog e as acoes atualizar/adiar.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.info,
    required this.next,
    required this.busy,
    required this.autofocus,
    required this.onUpdate,
    required this.onDefer,
  });

  final AddonInfo info;
  final AddonManifest next;
  final bool busy;
  final bool autofocus;
  final VoidCallback onUpdate;
  final VoidCallback onDefer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.manifest.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'v${info.manifest.version} → v${next.version}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Plataformas: ${next.supportedPlatforms.join(', ')}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              next.changelog ?? 'Sem notas desta versão.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FocusableButton(
                  label: 'Atualizar',
                  icon: Icons.system_update,
                  primary: true,
                  autofocus: autofocus,
                  onPressed: busy ? null : onUpdate,
                ),
                FocusableButton(
                  label: 'Adiar',
                  icon: Icons.schedule,
                  onPressed: busy ? null : onDefer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add-on com backup pre-update: oferece voltar a versao anterior.
class _RollbackTile extends StatelessWidget {
  const _RollbackTile({
    required this.info,
    required this.previous,
    required this.busy,
    required this.onRollback,
  });

  final AddonInfo info;
  final String previous;
  final bool busy;
  final VoidCallback onRollback;

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
                  Text(info.manifest.name,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Atual v${info.manifest.version} · '
                    'anterior v$previous',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            FocusableButton(
              label: 'Voltar para v$previous',
              icon: Icons.history,
              onPressed: busy ? null : onRollback,
            ),
          ],
        ),
      ),
    );
  }
}
