import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/exit_slider.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/slider_focus_ring.dart';

/// Barra de controles da TV (spec 27.6): composicao propria, nunca o
/// desktop ampliado. Largura limitada e centralizada (72% ate 760),
/// acoes principais a vista e audio/legenda/qualidade como chips com
/// rotulo textual que abrem os subpaineis. Acoes e tooltips iguais aos
/// do desktop: o D-pad e os testes enxergam a mesma operacao.
/// Apresentacao pura: toda acao passa pelo [MediaPlayerService].
class TvPlayerControls extends StatelessWidget {
  const TvPlayerControls({
    super.key,
    required this.player,
    required this.session,
    required this.onOpenPanel,
    this.videoTitle,
    this.settingsKey,
    this.sourceQualities = const [],
    this.sourceQualityListenable,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Abre o painel direto na subview, ancorado no contexto clicado.
  final void Function(PlayerPanelView view, BuildContext anchor) onOpenPanel;

  /// Titulo centralizado na primeira linha (null esconde).
  final String? videoTitle;

  /// Chave da engrenagem (ancora do painel, spec 3.5).
  final Key? settingsKey;

  /// Rendicoes da fonte + selecao ao vivo (rotulo do chip Qualidade).
  final List<SourceQuality> sourceQualities;
  final ValueListenable<String?>? sourceQualityListenable;

  @override
  Widget build(BuildContext context) {
    final tokens = TvLayout.tokensOf(context);
    final duration = session.duration ?? Duration.zero;
    final position = session.position;
    final max = duration.inMilliseconds.toDouble();
    final value =
        max <= 0 ? 0.0 : position.inMilliseconds.toDouble().clamp(0.0, max);
    final isPlaying = session.status == PlaybackStatus.playing;
    final gap = TvLayout.spacing(context, 12);

    return Theme(
      data: PlayerTheme.playerSurface(Theme.of(context)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Largura limitada e centralizada: sem ocupar quase toda a
          // tela em nenhuma classe (spec 27.6).
          final maxWidth =
              (constraints.maxWidth * 0.72).clamp(0.0, 760.0);
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
                      borderRadius:
                          BorderRadius.circular(tokens.panelRadius),
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
                            _TvTimeLabel(position.timestamp,
                                fontSize: tokens.textBody),
                            if (videoTitle != null)
                              Expanded(
                                child: Text(
                                  videoTitle!,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: PlayerTheme.primaryText,
                                    fontSize: tokens.textTitle,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                            _TvTimeLabel(duration.timestamp,
                                fontSize: tokens.textBody),
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
                                  : (v) => player.seek(Duration(
                                      milliseconds: v.round())),
                            ),
                          ),
                        ),
                        SizedBox(height: gap / 2),
                        Row(
                          children: [
                            _TvVolumeControl(
                              player: player,
                              session: session,
                              showSlider: maxWidth >= 520,
                              trackWidth: tokens.volumeTrackWidth,
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
                                    tooltip: isPlaying
                                        ? 'Pausar'
                                        : 'Reproduzir',
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
                              builder: (anchorContext) =>
                                  RoundPlayerButton(
                                key: settingsKey,
                                tooltip: 'Configurações',
                                icon: Icons.settings,
                                onPressed: () => onOpenPanel(
                                    PlayerPanelView.main, anchorContext),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: gap / 2),
                        _TvSubpanelChips(
                          session: session,
                          sourceQualities: sourceQualities,
                          sourceQualityListenable:
                              sourceQualityListenable,
                          onOpenPanel: onOpenPanel,
                        ),
                      ],
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
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _TvVolumeControl extends StatelessWidget {
  const _TvVolumeControl({
    required this.player,
    required this.session,
    required this.showSlider,
    required this.trackWidth,
  });

  final MediaPlayerService player;
  final PlaybackSession session;
  final bool showSlider;
  final double trackWidth;

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
            width: trackWidth,
            child: SliderFocusRing(
              child: ExitSlider(
                // Na fileira nao ha para onde descer: sai para o mudo,
                // vizinho da esquerda.
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

/// Chips com rotulo textual (spec 27.7: sem duvida de simbolo) que
/// abrem os subpaineis de audio, legendas e qualidade (spec 27.6).
class _TvSubpanelChips extends StatelessWidget {
  const _TvSubpanelChips({
    required this.session,
    required this.sourceQualities,
    required this.sourceQualityListenable,
    required this.onOpenPanel,
  });

  final PlaybackSession session;
  final List<SourceQuality> sourceQualities;
  final ValueListenable<String?>? sourceQualityListenable;
  final void Function(PlayerPanelView view, BuildContext anchor) onOpenPanel;

  @override
  Widget build(BuildContext context) {
    final listenable = sourceQualityListenable;
    if (listenable == null) return _chips(context, null);
    // Rotulo da qualidade acompanha a troca ao vivo, sem reabrir.
    return ValueListenableBuilder<String?>(
      valueListenable: listenable,
      builder: (context, selectedId, _) => _chips(context, selectedId),
    );
  }

  Widget _chips(BuildContext context, String? selectedSourceId) {
    final tokens = TvLayout.tokensOf(context);
    final audio =
        _trackLabel(session.audioTracks, session.selectedAudioId) ??
            'Padrão';
    final subtitles = _trackLabel(
            session.subtitleTracks, session.selectedSubtitleId) ??
        'Desativadas';
    final quality = _sourceLabel(selectedSourceId) ??
        _trackLabel(session.videoTracks, session.selectedVideoId) ??
        'Automática';
    Widget chip({
      required IconData icon,
      required String title,
      required String value,
      required PlayerPanelView view,
    }) {
      return Builder(
        builder: (anchorContext) => Tooltip(
              message: '$title: $value',
              child: OutlinedButton.icon(
                onPressed: () => onOpenPanel(view, anchorContext),
                icon: Icon(icon, size: tokens.iconSecondary),
                // Titulo em cima, valor embaixo: o valor nunca some
                // atras de ellipsis do prefixo, em nenhuma classe.
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: PlayerTheme.secondaryText,
                        fontSize: tokens.textCaption,
                      ),
                    ),
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: tokens.textBody),
                    ),
                  ],
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PlayerTheme.primaryText,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: Color(0xFF3A3A3C)),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(tokens.panelRadius),
                  ),
                  minimumSize: Size(0, tokens.controlHeight),
                ),
              ),
            ),
      );
    }

    // Uma linha em qualquer largura: tres espacos iguais, rotulo com
    // ellipsis e altura do token. Nada de viewport preguicoso (cortaria
    // chips) nem de quebra de linha (estouraria a 720p).
    final gap = TvLayout.spacing(context, 8);
    return Row(
      children: [
        Expanded(
          child: chip(
            icon: Icons.audiotrack,
            title: 'Áudio',
            value: audio,
            view: PlayerPanelView.audio,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: chip(
            icon: Icons.closed_caption,
            title: 'Legendas',
            value: subtitles,
            view: PlayerPanelView.subtitles,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: chip(
            icon: Icons.high_quality,
            title: 'Qualidade',
            value: quality,
            view: PlayerPanelView.quality,
          ),
        ),
      ],
    );
  }

  String? _sourceLabel(String? id) {
    if (id == null) return null;
    for (final quality in sourceQualities) {
      if (quality.id == id) return quality.label;
    }
    return null;
  }

  static String? _trackLabel(List<MediaTrack> tracks, String? id) {
    if (id == null) return null;
    for (final track in tracks) {
      if (track.id == id) return track.label;
    }
    return null;
  }
}
