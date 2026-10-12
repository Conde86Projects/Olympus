import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';

/// Detalhes de um add-on (spec 6.1, 6.1.1): identificacao, estado,
/// permissoes e acoes ativar/desativar/editar/atualizar/remover.
/// Origem nova de feed exige aprovacao explicita antes de ativar; a
/// remocao pede confirmacao e nunca toca as midias do usuario.
class AddonDetailsScreen extends StatefulWidget {
  const AddonDetailsScreen({
    super.key,
    required this.dependencies,
    required this.addonId,
  });

  final AppDependencies dependencies;
  final String addonId;

  @override
  State<AddonDetailsScreen> createState() => _AddonDetailsScreenState();
}

class _AddonDetailsScreenState extends State<AddonDetailsScreen> {
  bool _busy = false;

  AddonInfo? get _info =>
      widget.dependencies.addonService.findById(widget.addonId);

  @override
  Widget build(BuildContext context) {
    final addons = widget.dependencies.addonService;
    return AnimatedBuilder(
      animation: addons,
      builder: (context, _) {
        final info = _info;
        if (info == null) {
          return AppShell(
            title: 'Add-on',
            showBack: true,
            body: EmptyState(
              icon: Icons.extension_outlined,
              title: 'Add-on não encontrado',
              message: 'Ele pode ter sido removido.',
              actions: [
                FocusableButton(
                  label: 'Voltar',
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        // Erro tambem oferece desativar: silencia o defeito com um
        // toque (a reativacao revalida). So inativo/atualizacao
        // oferecem ativar.
        final canDisable = info.state == AddonState.active ||
            info.state == AddonState.error;
        final hasFeed = info.manifest.catalogUrl != null;
        return AppShell(
          title: info.manifest.name,
          showBack: true,
          body: ListView(
            children: [
              Text(
                'v${info.manifest.version} · ${info.manifest.author}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(addonStateIcon(info.state),
                      size: 18,
                      color: info.state == AddonState.error
                          ? Theme.of(context).colorScheme.error
                          : null),
                  const SizedBox(width: 8),
                  Text(
                    addonStateLabel(info.state),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              if (info.needsApproval) ...[
                const SizedBox(height: 12),
                _ApprovalCard(
                  info: info,
                  busy: _busy,
                  onApprove: () => _approve(info),
                ),
              ],
              if (info.updateAvailable) ...[
                const SizedBox(height: 12),
                FocusableButton(
                  label: 'Ver atualização disponível',
                  icon: Icons.system_update,
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.addonUpdates,
                  ),
                ),
              ],
              if (info.diagnostic != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    info.diagnostic!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FocusableButton(
                    label: canDisable ? 'Desativar' : 'Ativar',
                    icon:
                        canDisable ? Icons.toggle_off : Icons.toggle_on,
                    primary: !canDisable,
                    autofocus: true,
                    onPressed: _busy
                        ? null
                        : () => canDisable
                            ? addons.disable(info.manifest.id)
                            : addons.enable(info.manifest.id),
                  ),
                  FocusableButton(
                    label: 'Editar endereço',
                    icon: Icons.edit_outlined,
                    onPressed:
                        _busy ? null : () => _editSourceUrl(info),
                  ),
                  if (hasFeed)
                    FocusableButton(
                      label: 'Atualizar catálogo',
                      icon: Icons.refresh,
                      onPressed: _busy ? null : () => _refresh(info),
                    ),
                  FocusableButton(
                    label: 'Remover',
                    icon: Icons.delete_outline,
                    onPressed: _busy ? null : () => _confirmRemove(info),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              _Row(
                  title: 'Descrição', value: info.manifest.description),
              _Row(
                title: 'Origem',
                value:
                    '${info.manifest.repository}${info.originTrusted ? '' : ' (não verificada)'}',
              ),
              if (hasFeed)
                _Row(
                    title: 'Feed', value: info.manifest.catalogUrl!),
              _Row(
                title: 'Permissões',
                value: info.manifest.permissions.isEmpty
                    ? 'Nenhuma'
                    : info.manifest.permissions
                        .map(formatAddonPermission)
                        .join('\n'),
              ),
              _Row(
                  title: 'Conteúdo',
                  value: info.manifest.contentTypes.join(', ')),
              _Row(
                  title: 'Plataformas',
                  value: info.manifest.supportedPlatforms.join(', ')),
              _Row(
                  title: 'Instalado em',
                  value: _date(info.installedAt)),
              if (info.updatedAt != null)
                _Row(
                    title: 'Atualizado em',
                    value: _date(info.updatedAt!)),
              _Row(title: 'Página', value: info.manifest.homepage),
              _Row(
                  title: 'Aviso legal',
                  value: info.manifest.legalNotice),
            ],
          ),
        );
      },
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _approve(AddonInfo info) async {
    setState(() => _busy = true);
    try {
      await widget.dependencies.addonService
          .approveSource(info.manifest.id);
      _say('Origem aprovada. Ative a fonte para usar.');
    } on AddonError catch (error) {
      _say(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(AddonInfo info) async {
    setState(() => _busy = true);
    try {
      final count = await widget.dependencies.addonService
          .refreshSource(info.manifest.id);
      _say(count == 1
          ? 'Catálogo atualizado: 1 item.'
          : 'Catálogo atualizado: $count itens.');
    } on AddonError catch (error) {
      _say(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSourceUrl(AddonInfo info) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditSourceDialog(
        initialUrl: info.manifest.catalogUrl ?? '',
        onSave: (url) => widget.dependencies.addonService
            .updateSourceUrl(info.manifest.id, url),
      ),
    );
    if (saved != true || !mounted) return;
    final updated = _info;
    if (updated != null && updated.needsApproval) {
      _say('Endereço atualizado. Aprove a nova origem para ativar.');
    } else {
      _say('Endereço atualizado.');
    }
  }

  Future<void> _confirmRemove(AddonInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover add-on?'),
        content: const Text(
            'Remove o add-on e seus dados. Suas mídias não serão apagadas.'),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6): no D-pad o OK
          // imediato cancela com seguranca, nunca destroi.
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
    if ((confirmed ?? false) && mounted) {
      await widget.dependencies.addonService.uninstall(info.manifest.id);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// Dialogo de edicao do feed: Stateful proprio para o controller
/// morrer no tempo do framework (dispose manual apos o pop corre
/// contra o caret agendado do campo com autofocus).
class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.initialUrl, required this.onSave});

  final String initialUrl;
  final Future<void> Function(String url) onSave;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialUrl);
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar endereço do feed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DpadFieldExit(
            controller: _controller,
            child: TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'URL do feed JSON',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  // Navigator capturado antes do gap: o context do
                  // build nao vale depois do await.
                  final navigator = Navigator.of(context);
                  setState(() {
                    _errorText = null;
                    _saving = true;
                  });
                  try {
                    await widget.onSave(_controller.text);
                    if (mounted) navigator.pop(true);
                  } on AddonError catch (error) {
                    if (mounted) {
                      setState(() {
                        _errorText = error.message;
                        _saving = false;
                      });
                    }
                  }
                },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Cartao de aprovacao pendente (spec 6.1.1): mostra a origem nova e
/// exige o aceite explicito. Aprovar nao ativa sozinho.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.info,
    required this.busy,
    required this.onApprove,
  });

  final AddonInfo info;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = info.manifest.catalogUrl ?? '';
    final host = Uri.tryParse(url)?.host ?? url;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline,
                  size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nova origem não aprovada: $host',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'O endereço do feed mudou. Confira e aprove para poder ativar.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FocusableButton(
            label: 'Aprovar origem',
            icon: Icons.verified_outlined,
            primary: true,
            onPressed: busy ? null : onApprove,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
