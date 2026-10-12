import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/focusable_button.dart';
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
  });

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
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(16),
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
            child: Column(
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
                          : (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Janela estreita (compacto/retrato): some o trilho
                    // de volume para a fileira nunca estourar; o mudo
                    // continua disponivel.
                    final narrow = constraints.maxWidth < 460;
                    return Row(
                      children: [
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
                                onPressed: () => player
                                    .seekBy(-AppConstants.seekStep),
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
                                onPressed: () => player
                                    .seekBy(AppConstants.seekStep),
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
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
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
