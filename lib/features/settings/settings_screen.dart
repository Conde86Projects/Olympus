import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/features/settings/language_picker_page.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/tv_info_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/slider_focus_ring.dart';
import 'package:player/widgets/app_switch_theme.dart';

/// Configuracoes do aplicativo (spec 16): aparencia, reproducao, legendas,
/// audio, janela, atalhos, armazenamento e sobre. Todas ligadas ao
/// [PreferencesService]. Os idiomas preferidos usam o seletor navegável
/// ([LanguagePickerPage]) em vez de campo de texto: na TV física o IME
/// come as setas com o campo focado e o D-pad prende.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Rótulo do idioma atual (null/vazio = padrão do sistema).
  String _languageLabel(String? code) {
    if (code == null || code.trim().isEmpty) return 'Padrão do sistema';
    return languageDisplayName(code);
  }

  void _openLanguagePicker({
    required String title,
    required String? currentValue,
    required ValueChanged<String?> onSelected,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LanguagePickerPage(
          title: title,
          current: currentValue,
          onSelected: (v) {
            onSelected(v);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.dependencies.preferencesService;
    return AppShell(
      title: 'Configurações',
      showBack: true,
      body: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) {
          final current = prefs.current;
          return ListView(
            children: [
              _Section('Aparência', [
                ListTile(
                  title: const Text('Tema'),
                  subtitle: Text(current.theme == AppThemeMode.dark
                      ? 'Escuro'
                      : 'Sistema'),
                  trailing: Switch(
                    autofocus: true,
                    value: current.theme == AppThemeMode.system,
                    onChanged: (v) => prefs.update(current.copyWith(
                      theme: v ? AppThemeMode.system : AppThemeMode.dark,
                    )),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Animações'),
                  subtitle:
                      const Text('Transições de tela e do painel do player'),
                  value: current.animations,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(animations: v)),
                ),
                SwitchListTile(
                  title: const Text('Modo TV'),
                  subtitle:
                      const Text('Controles e textos maiores para a sala'),
                  value: current.tvMode,
                  onChanged: (v) => prefs
                      .update(current.copyWith(tvMode: v, tvModeAuto: false)),
                ),
                SwitchListTile(
                  title: const Text('Detectar TV automaticamente'),
                  subtitle:
                      const Text('Liga o modo TV sozinho em aparelho Leanback'),
                  value: current.tvModeAuto,
                  onChanged: (v) async {
                    if (!v) {
                      await prefs.update(current.copyWith(tvModeAuto: false));
                      return;
                    }
                    final isTv = await const TvInfoService().isTv;
                    if (!mounted) return;
                    await prefs.update(
                        current.copyWith(tvModeAuto: true, tvMode: isTv));
                  },
                ),
              ]),
              _Section('Reprodução', [
                SwitchListTile(
                  title: const Text('Reproduzir ao abrir'),
                  subtitle: const Text('Inicia o vídeo sozinho ao abrir'),
                  value: current.autoplay,
                  onChanged: (v) => prefs.update(current.copyWith(autoplay: v)),
                ),
                SwitchListTile(
                  title: const Text('Reproduzir próximo automaticamente'),
                  value: current.autoplayNext,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(autoplayNext: v)),
                ),
                SwitchListTile(
                  title: const Text('Lembrar posição'),
                  subtitle: const Text('Salva onde você parou em cada vídeo'),
                  value: current.rememberPosition,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(rememberPosition: v)),
                ),
                SwitchListTile(
                  title: const Text('Retomar de onde parou'),
                  subtitle: const Text('Volta ao ponto salvo ao abrir o vídeo'),
                  value: current.resumeAutomatically,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(resumeAutomatically: v)),
                ),
                ListTile(
                  title: const Text('Velocidade padrão'),
                  subtitle:
                      Text('${current.defaultSpeed}x'.replaceAll('.', ',')),
                  trailing: DropdownButton<double>(
                    value: AppConstants.speeds.contains(current.defaultSpeed)
                        ? current.defaultSpeed
                        : 1.0,
                    items: AppConstants.speeds
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text('${s}x'.replaceAll('.', ',')),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        prefs.update(current.copyWith(defaultSpeed: v));
                      }
                    },
                  ),
                ),
                // Android: escape para decodificador de TV com defeito
                // (a saida direta do MediaCodec e o padrao).
                if (defaultTargetPlatform == TargetPlatform.android)
                  SwitchListTile(
                    title: const Text('Modo de vídeo compatível'),
                    subtitle: Text(
                      (widget.dependencies.videoOutputGuard?.autoCompatible ??
                              false)
                          ? 'Ligado sozinho após falhas no vídeo. '
                              'Vale ao reabrir o app.'
                          : 'Use se o vídeo travar ou aparecer com falhas. '
                              'Vale ao reabrir o app.',
                    ),
                    value: current.compatibleVideoOutput ||
                        (widget.dependencies.videoOutputGuard
                                ?.autoCompatible ??
                            false),
                    onChanged: (v) async {
                      if (!v) {
                        await widget.dependencies.videoOutputGuard?.reset();
                      }
                      await prefs.update(
                          current.copyWith(compatibleVideoOutput: v));
                      if (mounted) setState(() {});
                    },
                  ),
              ]),
              _Section('Legendas', [
                SwitchListTile(
                  title: const Text('Ativar por padrão'),
                  value: current.subtitlesByDefault,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(subtitlesByDefault: v)),
                ),
                ListTile(
                  title: const Text('Idioma preferido'),
                  subtitle: Text(_languageLabel(current.defaultSubtitle)),
                  onTap: () => _openLanguagePicker(
                    title: 'Idioma das legendas',
                    currentValue: current.defaultSubtitle,
                    onSelected: (v) => prefs.update(current.copyWith(
                      defaultSubtitle: () => v,
                    )),
                  ),
                ),
              ]),
              _Section('Áudio', [
                ListTile(
                  title: const Text('Volume inicial'),
                  subtitle: Text('${(current.initialVolume * 100).round()}%'),
                ),
                SliderFocusRing(
                  child: ExitSlider(
                    // F11 (TV fisica): sem saida, o D-pad prendia aqui -
                    // o Slider consome as quatro setas. OK desce a lista.
                    exit: TraversalDirection.down,
                    child: Slider(
                      value: current.initialVolume,
                      onChanged: (v) =>
                          prefs.update(current.copyWith(initialVolume: v)),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Idioma preferido'),
                  subtitle: Text(_languageLabel(current.defaultAudio)),
                  onTap: () => _openLanguagePicker(
                    title: 'Idioma do áudio',
                    currentValue: current.defaultAudio,
                    onSelected: (v) => prefs.update(current.copyWith(
                      defaultAudio: () => v,
                    )),
                  ),
                ),
              ]),
              _Section('Janela', [
                SwitchListTile(
                  title: const Text('Sempre no topo'),
                  subtitle: const Text('Depende do sistema operacional'),
                  value: current.alwaysOnTop,
                  onChanged: (v) async {
                    await prefs.update(current.copyWith(alwaysOnTop: v));
                    await widget.dependencies.windowService.setAlwaysOnTop(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Iniciar em tela cheia'),
                  subtitle: const Text('Vale a partir da próxima abertura'),
                  value: current.startInFullscreen,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(startInFullscreen: v)),
                ),
                SwitchListTile(
                  title: const Text('Restaurar tamanho e posição'),
                  subtitle: const Text('Reabre a janela como estava antes'),
                  value: current.restoreWindowGeometry,
                  onChanged: (v) =>
                      prefs.update(current.copyWith(restoreWindowGeometry: v)),
                ),
              ]),
              // Referencia de leitura: a spec manda deixar os atalhos
              // configuraveis "futuramente" (12.3), nao nesta versao.
              const _Section('Atalhos', [
                _ShortcutRow(keys: 'Espaço', action: 'Reproduzir / pausar'),
                _ShortcutRow(
                    keys: 'Enter', action: 'Ativar focado / sair do ajuste'),
                _ShortcutRow(
                    keys: '←  →', action: 'Navegar (buscar 10 s, se ocultos)'),
                _ShortcutRow(
                    keys: '↑  ↓', action: 'Navegar (volume, se ocultos)'),
                _ShortcutRow(keys: 'M', action: 'Mudo'),
                _ShortcutRow(keys: 'F', action: 'Tela cheia'),
                _ShortcutRow(keys: 'I', action: 'Informações do vídeo'),
                _ShortcutRow(keys: 'S', action: 'Legendas'),
                _ShortcutRow(keys: 'A', action: 'Áudio'),
                _ShortcutRow(keys: 'C', action: 'Modo cinema'),
                _ShortcutRow(keys: 'Esc', action: 'Fechar painel / voltar'),
                _ShortcutRow(keys: 'Q', action: 'Fechar player'),
              ]),
              _Section('Armazenamento', [
                ListTile(
                  title: const Text('Limpar histórico'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirm(
                    context,
                    'Limpar histórico?',
                    'Remove o registro de vídeos assistidos. Seus arquivos não serão apagados.',
                    () => widget.dependencies.historyService.clear(),
                  ),
                ),
                ListTile(
                  title: const Text('Limpar dados do aplicativo'),
                  subtitle: const Text(
                      'Apaga preferências e histórico. Nunca apaga seus vídeos.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirm(
                    context,
                    'Limpar dados do aplicativo?',
                    'Suas preferências e histórico serão apagados. Seus arquivos de vídeo não serão tocados.',
                    () async {
                      await widget.dependencies.historyService.clear();
                      await prefs.clearLocalData();
                    },
                  ),
                ),
              ]),
              _Section('Suporte', [
                ListTile(
                  title: const Text('Diagnóstico e recuperação'),
                  subtitle: const Text('Estado do app, modo seguro e reparo.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.diagnostics,
                  ),
                ),
              ]),
              const _Section('Sobre', [
                ListTile(
                  title: Text('Player'),
                  subtitle:
                      Text('Versão ${AppConstants.appVersion} — protótipo'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          // Cancelar nasce focado (Fase 4, §26.6).
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await action();
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Na TV, cabecalho mais justo (menus compactos, spec 27.7).
          padding: TvMode.of(context)
              ? const EdgeInsets.fromLTRB(16, 10, 16, 2)
              : const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        // Interruptor padrao do app em todas as plataformas (o Switch
        // M3 roubava a cena); ver docs/PADROES_VISUAIS.md.
        for (final child in children)
          if (child is SwitchListTile ||
              (child is ListTile && child.trailing is Switch))
            AppSwitchTheme(child: child)
          else
            child,
        const Divider(),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(action),
      trailing: Text(
        keys,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
