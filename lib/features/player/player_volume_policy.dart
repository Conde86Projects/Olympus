import 'package:player/core/utils/volume_step.dart';
import 'package:player/services/media_player_service.dart';

/// Política do volume interno (desktop, setas ocultas): passo de 0,05 entre
/// 0,0 e 1,0, com fila do último alvo pedido e salvamento como volume
/// inicial. Extraída de player_screen.dart sem mudança de comportamento.
///
/// O motor e o salvamento entram como dependências: a política não conhece
/// preferências nem a tela.
class PlayerVolumePolicy {
  PlayerVolumePolicy({
    required MediaPlayerService player,
    required double Function() currentVolume,
    required void Function(double volume) savePreference,
  })  : _player = player,
        _currentVolume = currentVolume,
        _savePreference = savePreference;

  final MediaPlayerService _player;

  /// Volume da sessão, usado só quando não há alvo pendente.
  final double Function() _currentVolume;

  final void Function(double volume) _savePreference;

  /// Último alvo pedido e ainda não aplicado. Setas rápidas partem dele, não
  /// do volume da sessão (que chega pela stream e pode atrasar).
  double? _target;

  /// Próximo passo a partir do alvo pendente (ou do volume atual), aplicado
  /// ao motor e salvo como inicial depois que o motor confirma.
  Future<void> step(int direction) {
    final next = steppedVolume(_target ?? _currentVolume(), direction);
    _target = next;
    return _apply(next);
  }

  /// Salva [volume] como volume inicial, sem tocar no motor (slider do
  /// desktop e confirmação do celular).
  Future<void> persist(double volume) async => _savePreference(volume);

  Future<void> _apply(double next) async {
    try {
      await _player.setVolume(next);
      await persist(next);
    } finally {
      if (_target == next) _target = null;
    }
  }
}
