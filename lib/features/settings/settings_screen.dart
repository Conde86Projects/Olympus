import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/app.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/features/settings/language_picker_page.dart';
import 'package:player/features/settings/subtitle_appearance_rows.dart';
import 'package:player/models/preferences.dart';
import 'package:player/models/shortcut_action.dart';
import 'package:player/services/tv_info_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/slider_focus_ring.dart';
import 'package:player/widgets/app_switch_theme.dart';
import 'package:player/widgets/confirm_dialog.dart';

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

  /// Captura a proxima tecla para [action]. Recusa teclas reservadas e
  /// as que outra acao ja usa, dizendo o motivo na propria janela.
  Future<void> _captureShortcut(ShortcutAction action) async {
    final prefs = widget.dependencies.preferencesService;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.handled;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.f11) {
              setLocal(() => error = 'F11 já entra e sai da tela cheia.');
              return KeyEventResult.handled;
            }
            if (reservedShortcutKeys.contains(key)) {
              setLocal(() => error =
                  '${shortcutKeyLabel(key)} é uma tecla reservada para a navegação.');
              return KeyEventResult.handled;
            }
            if (!isAssignableShortcutKey(key)) {
              setLocal(() => error = 'Essa tecla não pode ser usada.');
              return KeyEventResult.handled;
            }
            final current = prefs.current;
            for (final other in ShortcutAction.values) {
              if (other != action && current.keyFor(other) == key) {
                setLocal(() => error =
                    '${shortcutKeyLabel(key)} já é usada em "${other.label}".');
                return KeyEventResult.handled;
              }
            }
            final updated = {...current.shortcuts};
            if (key == action.defaultKey) {
              updated.remove(action);
            } else {
              updated[action] = key;
            }
            prefs.update(current.copyWith(shortcuts: updated));
            Navigator.of(dialogContext).pop();
            return KeyEventResult.handled;
          },
          child: AlertDialog(
            title: Text(action.label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pressione a nova tecla'),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
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
                ListTile(
                  title: const Text('Tamanho do texto'),
                  trailing: DropdownButton<TextSizeOption>(
                    value: current.textSize,
                    items: [
                      for (final option in TextSizeOption.values)
                        DropdownMenuItem(
                            value: option, child: Text(option.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        prefs.update(current.copyWith(textSize: v));
                      }
                    },
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
                ...subtitleAppearanceRows(prefs),
              ]),
              _Section('Áudio', [
                // Volume interno (initialVolume) só vale no desktop/Windows.
                // No celular e na TV vale o volume do aparelho (botões
                // físicos / VOL+/VOL− do controle) e o app oferece só o
                // mudo: sem trilho nessas plataformas.
                if (TvMode.of(context) || MobileMode.of(context))
                  const ListTile(
                    title: Text('Volume inicial'),
                    subtitle: Text(
                        'Usa o volume do aparelho (só o mudo no app)'),
                  )
                else ...[
                  ListTile(
                    title: const Text('Volume inicial'),
                    subtitle:
                        Text('${(current.initialVolume * 100).round()}%'),
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
                ],
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
              _Section('Menu principal', [
                for (final destination in MainDestination.values)
                  SwitchListTile(
                    title: Text(destination.label),
                    value: !current.hiddenDestinations.contains(destination),
                    onChanged: (visible) => prefs.update(current.copyWith(
                      hiddenDestinations: [
                        for (final d in MainDestination.values)
                          if (d == destination
                              ? !visible
                              : current.hiddenDestinations.contains(d))
                            d,
                      ],
                    )),
                  ),
              ]),
              _Section('Add-ons', [
                SwitchListTile(
                  title: const Text('Permitir fontes desconhecidas'),
                  subtitle:
                      const Text('Libera a entrada de origens novas'),
                  value: current.allowUnknownSources,
                  onChanged: (v) async {
                    if (!v) {
                      await prefs.update(
                          current.copyWith(allowUnknownSources: false));
                      return;
                    }
                    if (!context.mounted) return;
                    final confirmed =
                        await confirmEnableUnknownSources(context);
                    if (confirmed) {
                      await prefs.update(prefs.current
                          .copyWith(allowUnknownSources: true));
                    }
                  },
                ),
              ]),
              // Atalhos: editaveis no computador e na TV (teclado/controle).
              // No celular sem teclado a secao e so referencia: nao ha como
              // pressionar a nova tecla, entao nada de edicao nem restaurar.
              _Section('Atalhos', [
                for (final action in ShortcutAction.values)
                  ListTile(
                    dense: true,
                    title: Text(action.label),
                    trailing: Text(shortcutKeyLabel(current.keyFor(action))),
                    onTap: MobileMode.of(context)
                        ? null
                        : () => _captureShortcut(action),
                  ),
                if (!MobileMode.of(context))
                  ListTile(
                    dense: true,
                    title: const Text('Restaurar padrão'),
                    trailing: const Icon(Icons.restart_alt),
                    onTap: () =>
                        prefs.update(current.copyWith(shortcuts: const {})),
                  ),
                const _ShortcutRow(
                    keys: 'Espaço', action: 'Reproduzir / pausar'),
                const _ShortcutRow(
                    keys: 'Enter', action: 'Ativar focado / sair do ajuste'),
                const _ShortcutRow(
                    keys: '←  →', action: 'Navegar (buscar 10 s, se ocultos)'),
                const _ShortcutRow(
                    keys: '↑  ↓',
                    action:
                        'Navegar (só reexibe na TV; volume no desktop, se ocultos)'),
                const _ShortcutRow(keys: 'Esc', action: 'Fechar painel / voltar'),
                const _ShortcutRow(keys: 'Tab', action: 'Próximo controle'),
                if (!MobileMode.of(context))
                  const _ShortcutRow(
                      keys: 'F11', action: 'Entrar / sair da tela cheia'),
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
                  title: Text('Olympus'),
                  subtitle:
                      Text('Versão ${AppConstants.appVersion}'),
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
