import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/slider_focus_ring.dart';

/// Botao do perfil compacto: 36 de diametro com glifo de 20 e
/// respiro 8 (20 + 2x8 = 36 exatos). Leve sem perder a regra dos
/// 3 metros: o D-pad nao precisa de alvo de toque.
const _buttonSize = 36.0;
const _buttonPadding = EdgeInsets.all(8);

/// Barra de controles da TV, perfil compacto obrigatorio (spec 27.6):
/// titulo, progresso, volume (icone mudo, sem trilho), voltar 10,
/// reproduzir/pausar, avancar 10 e Opcoes. Audio, legendas, qualidade
/// e repeticao moram no painel de Opcoes (linhas que abrem os
/// subpaineis): nada de chips fixos. Largura limitada e centralizada
/// (50% ate 460: 440 reais na TCL 960x540, apos a safe area e o teto
/// 880 da tela), botoes de 36 com glifos de 20, altura 105-125.
/// Tooltips iguais aos do desktop: o D-pad e os testes enxergam a
/// mesma operacao. Apresentacao pura: toda acao passa pelo
/// [MediaPlayerService].
class TvPlayerControls extends StatelessWidget {
  const TvPlayerControls({
    super.key,
    required this.player,
    required this.session,
    required this.onOpenPanel,
    this.videoTitle,
    this.settingsKey,
    this.systemMuted = false,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Abre o painel de Opcoes, ancorado no contexto clicado.
  final void Function(PlayerPanelView view, BuildContext anchor) onOpenPanel;

  /// Titulo em uma linha com reticencias (null esconde).
  final String? videoTitle;

  /// Chave da engrenagem (ancora do painel, spec 3.5).
  final Key? settingsKey;

  /// Sistema zerado/mudo (Android): o ícone reflete também o aparelho.
  final bool systemMuted;

  static double? _loggedPanelWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = TvLayout.tokensOf(context);
    final duration = session.duration ?? Duration.zero;
    final position = session.position;
    final max = duration.inMilliseconds.toDouble();
    final value =
        max <= 0 ? 0.0 : position.inMilliseconds.toDouble().clamp(0.0, max);
    final isPlaying = session.status == PlaybackStatus.playing;
    final gap = TvLayout.spacing(context, 8);

    return Theme(
      data: PlayerTheme.playerSurface(Theme.of(context)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Perfil compacto (spec 27.6): metade da largura ate 460.
          // Na TCL (880 uteis apos a safe area e o teto da tela) = 440,
          // uns 46% do viewport logico de 960.
          final maxWidth = (constraints.maxWidth * 0.50).clamp(0.0, 460.0);
          TvPanelMetrics.record(constraints, maxWidth);
          if (kDebugMode && _loggedPanelWidth != maxWidth) {
            _loggedPanelWidth = maxWidth;
            String bound(double v) =>
                v.isInfinite ? 'livre' : v.toStringAsFixed(0);
            debugPrint('[olympus][exibicao] painel '
                'restricoes=${bound(constraints.maxWidth)}x'
                '${bound(constraints.maxHeight)} '
                'aplicada=${maxWidth.toStringAsFixed(1)}');
          }
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.panelRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: EdgeInsets.all(gap),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(tokens.panelRadius),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          offset: Offset(0, 8),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    // Glifos de 20 em botoes de 36: presencia sem
                    // exagero, dentro dos 105-125 de altura.
                    child: IconTheme(
                      data: const IconThemeData(size: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (videoTitle != null)
                                Expanded(
                                  child: Text(
                                    videoTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: PlayerTheme.primaryText,
                                      fontSize: tokens.textCaption,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else
                                const Spacer(),
                              SizedBox(width: gap),
                              _TvTimeLabel(duration.timestamp,
                                  fontSize: tokens.textCaption),
                            ],
                          ),
                          SliderFocusRing(
                            padding: 2,
                            child: ExitSlider(
                              exit: TraversalDirection.down,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  // Trilho extra-fino (3) com dedao 8 e halo
                                  // 10: o slider mede 20 em vez de 24. O anel
                                  // de foco (anel de 3 no token) continua
                                  // sendo o indicador; o D-pad nao precisa
                                  // de alvo de toque.
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: value,
                                  max: max <= 0 ? 1 : max,
                                  onChanged: max <= 0
                                      ? null
                                      : (v) => player.seek(
                                          Duration(milliseconds: v.round())),
                                ),
                              ),
                            ),
                          ),
                          // Respiro minimo: o anel do slider ja separa.
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _TvVolumeControl(
                                player: player,
                                session: session,
                                systemMuted: systemMuted,
                              ),
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    RoundPlayerButton(
                                      tooltip: 'Retroceder 10 segundos',
                                      icon: Icons.replay_10,
                                      size: _buttonSize,
                                      padding: _buttonPadding,
                                      onPressed: () =>
                                          player.seekBy(-AppConstants.seekStep),
                                    ),
                                    RoundPlayerButton(
                                      autofocus: true,
                                      tooltip:
                                          isPlaying ? 'Pausar' : 'Reproduzir',
                                      icon: isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: _buttonSize,
                                      padding: _buttonPadding,
                                      onPressed: () => isPlaying
                                          ? player.pause()
                                          : player.play(),
                                    ),
                                    RoundPlayerButton(
                                      tooltip: 'Avançar 10 segundos',
                                      icon: Icons.forward_10,
                                      size: _buttonSize,
                                      padding: _buttonPadding,
                                      onPressed: () =>
                                          player.seekBy(AppConstants.seekStep),
                                    ),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (anchorContext) => RoundPlayerButton(
                                  key: settingsKey,
                                  tooltip: 'Configurações',
                                  icon: Icons.settings,
                                  size: _buttonSize,
                                  padding: _buttonPadding,
                                  onPressed: () => onOpenPanel(
                                      PlayerPanelView.main, anchorContext),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvTimeLabel extends StatelessWidget {
  const _TvTimeLabel(this.text, {required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: PlayerTheme.secondaryText,
        fontSize: fontSize,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Mudo do perfil compacto: so o icone, sem trilho. O D-pad nunca
/// altera o volume: ele sai nos botoes VOL+/VOL− do controle remoto
/// (volume da TV, fora do app); as setas navegam, buscam e reexibem.
class _TvVolumeControl extends StatelessWidget {
  const _TvVolumeControl({
    required this.player,
    required this.session,
    this.systemMuted = false,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Sistema zerado/mudo: o ícone reflete também o aparelho.
  final bool systemMuted;

  @override
  Widget build(BuildContext context) {
    final muted = session.displayMuted(systemMuted: systemMuted);
    return RoundPlayerButton(
      tooltip: muted ? 'Ativar som' : 'Silenciar',
      icon: muted ? Icons.volume_off : Icons.volume_up,
      size: _buttonSize,
      padding: _buttonPadding,
      onPressed: () => player.setMuted(!session.isMuted),
    );
  }
}
