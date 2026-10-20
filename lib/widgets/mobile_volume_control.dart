import 'package:flutter/material.dart';

import 'package:player/app/theme.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/focusable_button.dart';

/// Passo do controle de volume mobile (5%).
const mobileVolumeStep = 0.05;

/// Alvo minimo de toque no celular (Material: 48 dp).
const _touchTarget = 48.0;

/// Volume depois de um passo: arredondado ao passo (sem 0,3499999) e
/// limitado a 0.0–1.0.
double steppedVolume(double current, int direction) {
  final raw = current + direction * mobileVolumeStep;
  final snapped = (raw / mobileVolumeStep).round() * mobileVolumeStep;
  return (double.parse(snapped.toStringAsFixed(2))).clamp(0.0, 1.0);
}

/// Situacao do audio para os controles de volume.
enum MobileAudioState {
  /// Carregando: ainda nao da para afirmar se ha faixa de audio.
  pending,

  /// Faixa de audio confirmada: controles ativos.
  available,

  /// Midia carregada sem faixa de audio: controles desabilitados.
  missing,
}

/// Decide o estado do audio pela sessao. Durante o carregamento a lista
/// de faixas pode chegar vazia; so vira [MobileAudioState.missing] depois
/// que a midia esta tocando, pausada ou concluida.
MobileAudioState mobileAudioState(PlaybackSession session) {
  if (session.audioTracks.isNotEmpty) return MobileAudioState.available;
  return switch (session.status) {
    PlaybackStatus.playing ||
    PlaybackStatus.paused ||
    PlaybackStatus.completed =>
      MobileAudioState.missing,
    _ => MobileAudioState.pending,
  };
}

/// Controle de volume do celular: mudo, diminuir, aumentar e barra.
/// Estado vem da sessao (volume real, mudo real); o mudo guarda o volume
/// anterior no motor. Cada ajuste e reportado por [onVolumeCommitted]
/// para virar o volume inicial da preferencia.
class MobileVolumeControl extends StatelessWidget {
  const MobileVolumeControl({
    super.key,
    required this.player,
    required this.session,
    this.onVolumeCommitted,
    this.compact = false,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Recebe o novo volume (0.0–1.0) depois de cada passo.
  final ValueChanged<double>? onVolumeCommitted;

  /// Fileira unica da paisagem: barra estreita. Retrato usa a largura toda.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final audio = mobileAudioState(session);
    final enabled = audio == MobileAudioState.available;
    final shown = session.isMuted ? 0.0 : session.volume.clamp(0.0, 1.0);
    final percent = (shown * 100).round();
    final muted = session.isMuted || session.volume <= 0;

    void change(int direction) {
      final next = steppedVolume(shown, direction);
      if (session.isMuted) player.setMuted(false);
      player.setVolume(next);
      onVolumeCommitted?.call(next);
    }

    final region = _region(context, enabled, audio, shown, percent);

    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        RoundPlayerButton(
          tooltip: muted ? 'Ativar som' : 'Silenciar',
          icon: muted ? Icons.volume_off : Icons.volume_up,
          size: _touchTarget,
          padding: const EdgeInsets.all(12),
          onPressed: enabled ? () => player.setMuted(!session.isMuted) : null,
        ),
        RoundPlayerButton(
          tooltip: 'Diminuir volume',
          icon: Icons.remove,
          size: _touchTarget,
          padding: const EdgeInsets.all(12),
          onPressed: enabled ? () => change(-1) : null,
        ),
        if (compact)
          SizedBox(width: 96, child: region)
        else
          Expanded(child: region),
        RoundPlayerButton(
          tooltip: 'Aumentar volume',
          icon: Icons.add,
          size: _touchTarget,
          padding: const EdgeInsets.all(12),
          onPressed: enabled ? () => change(1) : null,
        ),
      ],
    );
  }

  Widget _region(BuildContext context, bool enabled, MobileAudioState audio,
      double shown, int percent) {
    if (audio == MobileAudioState.missing) {
      return Center(
        child: Text(
          'Sem áudio nesta mídia',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Semantics(
      label: 'Volume',
      value: enabled ? '$percent%' : 'indisponível',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: enabled ? shown : 0,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(
              enabled ? PlayerTheme.accent : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
