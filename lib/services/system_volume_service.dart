import 'package:flutter/services.dart';

/// Leitura do volume do sistema (Android: celular e TV). O app nunca
/// ajusta o volume do sistema — só observa, para refletir no ícone de
/// mudo (zerou no aparelho → mostra mudo; aumentou → despluga).
class SystemVolumeState {
  const SystemVolumeState({required this.volume, required this.muted});

  /// Volume entre 0.0 e 1.0.
  final double volume;

  /// Mudo do sistema (tecla MUTE do controle, por exemplo).
  final bool muted;

  /// Sem informação (desktop, testes): trata como som cheio.
  static const full = SystemVolumeState(volume: 1.0, muted: false);

  /// Efetivamente silencioso: mudo ou zerado.
  bool get isSilent => muted || volume <= 0.0;
}

/// Fonte do volume do sistema. Produção usa canal de plataforma no
/// Android; fora dele (desktop, testes) vale [NoOpSystemVolumeService].
abstract class SystemVolumeService {
  const SystemVolumeService();

  /// Cria a implementação da plataforma (Android observa; resto é NoOp).
  factory SystemVolumeService.platform() = _MethodChannelSystemVolumeService;

  /// Estado atual; falha vira [SystemVolumeState.full].
  Future<SystemVolumeState> current();

  /// Emite a cada mudança no sistema; erro encerra sem evento.
  Stream<SystemVolumeState> watch();
}

/// Fora do Android (e em testes sem canal): sempre som cheio.
class NoOpSystemVolumeService extends SystemVolumeService {
  const NoOpSystemVolumeService();

  @override
  Future<SystemVolumeState> current() async => SystemVolumeState.full;

  @override
  Stream<SystemVolumeState> watch() => const Stream.empty();
}

class _MethodChannelSystemVolumeService extends SystemVolumeService {
  static const _methods = MethodChannel('olympus/player/system_volume');
  static const _events = EventChannel('olympus/player/system_volume_events');

  static SystemVolumeState _parse(dynamic raw) {
    if (raw is Map) {
      final volume = (raw['volume'] as num?)?.toDouble() ?? 1.0;
      final muted = (raw['muted'] as bool?) ?? false;
      return SystemVolumeState(
        volume: volume.clamp(0.0, 1.0),
        muted: muted,
      );
    }
    return SystemVolumeState.full;
  }

  @override
  Future<SystemVolumeState> current() async {
    try {
      final raw = await _methods.invokeMethod<dynamic>('getState');
      return _parse(raw);
    } catch (_) {
      return SystemVolumeState.full;
    }
  }

  @override
  Stream<SystemVolumeState> watch() async* {
    try {
      await for (final raw in _events.receiveBroadcastStream()) {
        yield _parse(raw);
      }
    } catch (_) {
      // Sem canal (desktop/testes): encerra sem evento.
    }
  }
}
