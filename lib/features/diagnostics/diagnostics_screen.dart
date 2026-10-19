import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player/widgets/app_switch_theme.dart';
import 'package:flutter/services.dart';
import 'package:player/app/app.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/tv_info_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/app_toast.dart';

/// Diagnostico e recuperacao (spec 6.1): estado dos componentes, modo
/// seguro manual e acoes de reparo. Nenhuma acao toca midias. A mensagem
/// do ultimo erro aparece aqui (tela local), mas NUNCA no relatorio
/// exportado (ver [DiagnosticsService.buildReport]).
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Future<DiagnosticsReport>? _report;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _report = widget.dependencies.diagnosticsService.collect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Diagnóstico e recuperação',
      showBack: true,
      body: FutureBuilder<DiagnosticsReport>(
        future: _report,
        builder: (context, snapshot) {
          final report = snapshot.data;
          if (report == null) {
            return const Column(
              children: [
                SizedBox(height: 32),
                LinearProgressIndicator(),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StateCard(report: report),
                const SizedBox(height: 12),
                const _DisplayCard(),
                const SizedBox(height: 12),
                _SafeModeCard(
                  dependencies: widget.dependencies,
                  busy: _busy,
                  onChanged: _refresh,
                ),
                const SizedBox(height: 12),
                _RecoveryCard(
                  dependencies: widget.dependencies,
                  busy: _busy,
                  onBusy: (value) => setState(() => _busy = value),
                  onDone: _refresh,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Versao, plataforma e estado dos componentes.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.report});

  final DiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _Row(title: 'Versão', value: report.appVersion),
            _Row(title: 'Plataforma', value: report.platform),
            _Row(title: 'Player', value: report.playerLabel),
            _Row(
              title: 'Armazenamento',
              value: report.storageOk ? 'ok' : 'FALHA',
              error: !report.storageOk,
            ),
            _Row(title: 'Modo seguro', value: report.safeModeLabel),
            _Row(
              title: 'Biblioteca',
              value: '${report.libraryCount} vídeos, '
                  '${report.favoritesCount} favoritos',
            ),
            _Row(
              title: 'Histórico',
              value: '${report.historyCount} entradas',
            ),
            _Row(
              title: 'Add-ons',
              value: '${report.addonsTotal} instalados '
                  '(${report.addonsActive} ativos, '
                  '${report.addonsInactive} inativos, '
                  '${report.addonsError} em erro)',
            ),
            _Row(
              title: 'Repositórios',
              value: '${report.reposCount} cadastrados',
            ),
            _Row(
              title: 'Último erro',
              value: report.lastErrorAt ?? 'nenhum registrado',
            ),
            if (report.lastErrorKind != null)
              _Row(
                title: 'Tipo do erro',
                value: playbackErrorKindLabel(report.lastErrorKind!),
              ),
            if (report.lastErrorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  report.lastErrorMessage!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            _Row(
              title: 'Última alteração',
              value: report.lastChangeName ?? 'nenhuma',
            ),
          ],
        ),
      ),
    );
  }
}

/// Liga/desliga manual do modo seguro. Desativar nao e desinstalar: o
/// modo seguro so deixa os add-ons de fora do arranque.
class _SafeModeCard extends StatelessWidget {
  const _SafeModeCard({
    required this.dependencies,
    required this.busy,
    required this.onChanged,
  });

  final AppDependencies dependencies;
  final bool busy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guard = dependencies.startupGuard;
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modo seguro', style: theme.textTheme.titleMedium),
            AnimatedBuilder(
              animation: guard,
              builder: (context, _) => AppSwitchTheme(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativar modo seguro'),
                  subtitle: const Text('Vale a partir do próximo arranque.'),
                  value: guard.manualSafeMode,
                  onChanged: busy
                      ? null
                      : (value) async {
                          await guard.setManualSafeMode(value);
                          onChanged();
                        },
                ),
              ),
            ),
            Text(
              'O modo seguro não desinstala nada: só deixa os add-ons de '
              'fora do arranque.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Acoes de reparo: cada uma confirma o escopo antes de agir quando e
/// destrutiva. Midias nunca sao tocadas.
class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.dependencies,
    required this.busy,
    required this.onBusy,
    required this.onDone,
  });

  final AppDependencies dependencies;
  final bool busy;
  final ValueChanged<bool> onBusy;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = dependencies.diagnosticsService;
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recuperação', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            FocusableButton(
              label: 'Restaurar padrões',
              icon: Icons.settings_backup_restore,
              onPressed: busy
                  ? null
                  : () => _run(context, () async {
                        await service.restoreDefaults();
                        return 'Padrões restaurados. Biblioteca, histórico '
                            'e vídeos intactos.';
                      }),
            ),
            const SizedBox(height: 4),
            Text(
              'Só preferências. Biblioteca, histórico e vídeos intactos.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FocusableButton(
              label: 'Limpar cache',
              icon: Icons.cleaning_services,
              onPressed: busy
                  ? null
                  : () => _run(context, () async {
                        await service.clearEphemeral();
                        return 'Cache e registros temporários limpos.';
                      }),
            ),
            const SizedBox(height: 4),
            Text(
              'Apaga registros temporários de diagnóstico.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FocusableButton(
              label: 'Limpar dados do app',
              icon: Icons.delete_forever,
              onPressed: busy ? null : () => _confirmWipe(context),
            ),
            const SizedBox(height: 4),
            Text(
              'Apaga tudo do app. Seus vídeos não serão apagados.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FocusableButton(
              label: 'Exportar relatório',
              icon: Icons.copy,
              onPressed: busy
                  ? null
                  : () => _run(context, () async {
                        final report = await service.collect();
                        await Clipboard.setData(ClipboardData(
                          text: service.buildReport(report),
                        ));
                        return 'Relatório copiado (sem caminhos, URLs ou '
                            'credenciais).';
                      }),
            ),
            const SizedBox(height: 12),
            Text(
              service.reinstallInstructions(),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<String> Function() action,
  ) async {
    onBusy(true);
    try {
      final message = await action();
      onDone();
      if (context.mounted) {
        showAppToast(context, message);
      }
    } finally {
      if (context.mounted) onBusy(false);
    }
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar todos os dados do app?'),
        content: const Text(
            'Preferências, biblioteca, histórico, add-ons, repositórios e '
            'registros de recuperação serão apagados.\n\n'
            'Seus arquivos de vídeo NÃO serão tocados.'),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6).
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () async {
      await dependencies.diagnosticsService.clearAppData();
      return 'Dados do app apagados. Seus vídeos foram preservados.';
    });
  }
}

/// Exibicao real (spec 27): tamanho logico, densidade, resolucao
/// fisica, orientacao, plataforma, Leanback e as restricoes que a
/// barra TV recebeu. Base da validacao em hardware.
class _DisplayCard extends StatelessWidget {
  const _DisplayCard();

  static String _size(Size size) =>
      '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}';

  static String _bound(double value) =>
      value.isInfinite ? 'livre' : value.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final physical = View.of(context).physicalSize;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final panel = TvPanelMetrics.current;
    if (kDebugMode) {
      debugPrint('[olympus][exibicao] logico=${_size(size)} dpr=$dpr '
          'fisico=${_size(physical)} '
          'orientacao=${landscape ? 'paisagem' : 'retrato'} '
          'plataforma=${Platform.operatingSystem} '
          'classe=${TvLayout.widthClassOf(context).name}');
    }
    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exibição', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _Row(title: 'Tamanho lógico', value: _size(size)),
            _Row(title: 'Densidade', value: dpr.toString()),
            _Row(title: 'Resolução física', value: _size(physical)),
            _Row(
              title: 'Orientação',
              value: landscape ? 'paisagem' : 'retrato',
            ),
            _Row(title: 'Plataforma', value: Platform.operatingSystem),
            _Row(
              title: 'Classe de largura',
              value: TvLayout.widthClassOf(context).name,
            ),
            FutureBuilder<bool>(
              future: const TvInfoService().isTv,
              builder: (context, snapshot) => _Row(
                title: 'Leanback',
                value:
                    snapshot.hasData ? (snapshot.data! ? 'sim' : 'não') : '…',
              ),
            ),
            ValueListenableBuilder<TvPanelMetricsData?>(
              valueListenable: panel,
              builder: (context, metrics, _) => _Row(
                title: 'Painel TV',
                value: metrics == null
                    ? 'não exibido ainda'
                    : 'restrições ${_bound(metrics.constraints.maxWidth)} × ${_bound(metrics.constraints.maxHeight)} · aplicada ${metrics.appliedMaxWidth.toStringAsFixed(1)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.value, this.error = false});

  final String title;
  final String value;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(title, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: error ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
