import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:player/app/mobile_mode.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/mobile_volume_control.dart';
import 'package:player/widgets/slider_focus_ring.dart';

/// Card de controles flutuante sobre o video (spec 12.1, espirito
/// Showtime): tempo/titulo/duracao, progresso em largura total e a
/// fileira volume/transporte/configuracoes, num painel fosco com
/// margens — nunca grudado na borda. Apresentacao pura: toda acao
/// passa pelo [MediaPlayerService]. A tela cheia mora no canto
/// superior esquerdo (fora do card). Composicao do desktop (spec 27.2):
/// na TV, a tela usa o [TvPlayerControls], com tokens proprios.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.session,
    required this.onOpenSettings,
    this.videoTitle,
    this.settingsKey,
    this.dense = false,
    this.onVolumeCommitted,
  });

  /// Altura de janela abaixo da qual a tela usa o card [dense]. O
  /// minimo normal da janela e 600: so o compacto e janelas pequenas
  /// arrastadas ficam abaixo.
  static const denseMaxHeight = 420.0;

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Recebe o contexto do botao de engrenagem: o painel abre ancorado
  /// acima do icone clicado (padrao geral de menus, spec 3.5).
  final void Function(BuildContext anchorContext) onOpenSettings;

  /// Titulo centralizado na primeira linha (null esconde).
  final String? videoTitle;

  /// Chave do botao de configuracoes: atalhos de teclado (I/S/A) usam o
  /// contexto dela como ancora do painel (spec 3.5, 12.3).
  final Key? settingsKey;

  /// Janela baixa (compacto 480x270): uma fileira so, com transporte,
  /// tempo, progresso e configuracoes, botoes de 36 e sem titulo. O
  /// card normal cobria metade do video e encostava nos cantos.
  final bool dense;

  /// Volume ajustado pelo controle mobile (0.0–1.0). Nulo fora do celular:
  /// desktop e TV nao persistem volume por aqui.
  final ValueChanged<double>? onVolumeCommitted;

  @override
  Widget build(BuildContext context) {
    final duration = session.duration ?? Duration.zero;
    final position = session.position;
    final max = duration.inMilliseconds.toDouble();
    final value =
        max <= 0 ? 0.0 : position.inMilliseconds.toDouble().clamp(0.0, max);
    final isPlaying = session.status == PlaybackStatus.playing;

    return Theme(
      data: PlayerTheme.playerSurface(Theme.of(context)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: dense
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                : const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    12,
                  ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  offset: Offset(0, 8),
                  blurRadius: 24,
                ),
              ],
            ),
            child: dense
                ? _denseRow(context, position, duration, value, max, isPlaying)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _TimeLabel(position.timestamp),
                          if (videoTitle != null)
                            Expanded(
                              child: Text(
                                videoTitle!,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            )
                          else
                            const Spacer(),
                          _TimeLabel(duration.timestamp),
                        ],
                      ),
                      SliderFocusRing(
                        child: ExitSlider(
                          exit: TraversalDirection.down,
                          child: Slider(
                            value: value,
                            max: max <= 0 ? 1 : max,
                            onChanged: max <= 0
                                ? null
                                : (v) => player
                                    .seek(Duration(milliseconds: v.round())),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (MobileMode.of(context)) ...[
                        MobileVolumeControl(
                          player: player,
                          session: session,
                          onVolumeCommitted: onVolumeCommitted,
                        ),
                        const SizedBox(height: 4),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Janela estreita (compacto/retrato): some o trilho
                          // de volume para a fileira nunca estourar; o mudo
                          // continua disponivel.
                          final narrow = constraints.maxWidth < 460;
                          return Row(
                            children: [
                              if (!MobileMode.of(context))
                                _VolumeControl(
                                  player: player,
                                  session: session,
                                  showSlider: !narrow,
                                ),
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    RoundPlayerButton(
                                      tooltip: 'Retroceder 10 segundos',
                                      icon: Icons.replay_10,
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
                                      onPressed: () => isPlaying
                                          ? player.pause()
                                          : player.play(),
                                    ),
                                    RoundPlayerButton(
                                      tooltip: 'Avançar 10 segundos',
                                      icon: Icons.forward_10,
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
                                  onPressed: () =>
                                      onOpenSettings(anchorContext),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Fileira unica do card [dense]: mudo, transporte, tempo/progresso
  /// e configuracoes. Mesmos tooltips e acoes do card normal.
  Widget _denseRow(BuildContext context, Duration position, Duration duration,
      double value, double max, bool isPlaying) {
    // Celular em paisagem tambem cai aqui (altura < 420): alvos de 48.
    final touch = MobileMode.of(context);
    final size = touch ? MobileMode.minTouchTarget : 36.0;
    final padding = EdgeInsets.all(touch ? 12 : 6);
    final muted = session.isMuted || session.volume <= 0;
    return Row(
      children: [
        if (touch)
          MobileVolumeControl(
            player: player,
            session: session,
            onVolumeCommitted: onVolumeCommitted,
            compact: true,
          )
        else
          RoundPlayerButton(
            tooltip: muted ? 'Ativar som' : 'Silenciar',
            icon: muted ? Icons.volume_off : Icons.volume_up,
            size: size,
            padding: padding,
            onPressed: () => player.setMuted(!session.isMuted),
          ),
        RoundPlayerButton(
          tooltip: 'Retroceder 10 segundos',
          icon: Icons.replay_10,
          size: size,
          padding: padding,
          onPressed: () => player.seekBy(-AppConstants.seekStep),
        ),
        RoundPlayerButton(
          autofocus: true,
          tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: size,
          padding: padding,
          onPressed: () => isPlaying ? player.pause() : player.play(),
        ),
        RoundPlayerButton(
          tooltip: 'Avançar 10 segundos',
          icon: Icons.forward_10,
          size: size,
          padding: padding,
          onPressed: () => player.seekBy(AppConstants.seekStep),
        ),
        _TimeLabel(position.timestamp, dense: true),
        Expanded(
          child: SliderFocusRing(
            child: ExitSlider(
              exit: TraversalDirection.down,
              child: Slider(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                value: value,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (v) => player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
        ),
        _TimeLabel(duration.timestamp, dense: true),
        Builder(
          builder: (anchorContext) => RoundPlayerButton(
            key: settingsKey,
            tooltip: 'Configurações',
            icon: Icons.settings,
            size: size,
            padding: padding,
            onPressed: () => onOpenSettings(anchorContext),
          ),
        ),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text, {this.dense = false});

  final String text;

  /// Card de janela baixa: fonte 12 e coluna de 48.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: dense ? 48 : 56,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: (dense ? textTheme.bodySmall : textTheme.bodyMedium)
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.player,
    required this.session,
    this.showSlider = true,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Falso em janela estreita: so o mudo (sem estouro).
  final bool showSlider;

  @override
  Widget build(BuildContext context) {
    final muted = session.isMuted || session.volume <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundPlayerButton(
          tooltip: muted ? 'Ativar som' : 'Silenciar',
          icon: muted ? Icons.volume_off : Icons.volume_up,
          onPressed: () => player.setMuted(!session.isMuted),
        ),
        if (showSlider)
          SizedBox(
            width: 72,
            child: SliderFocusRing(
              child: ExitSlider(
                // Na fileira de botoes nao ha para onde descer: sai para o
                // mudo, vizinho da esquerda.
                exit: TraversalDirection.left,
                child: Slider(
                  value: session.isMuted ? 0 : session.volume,
                  onChanged: (v) {
                    player.setVolume(v);
                    if (v > 0 && session.isMuted) player.setMuted(false);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
