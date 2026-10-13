/// Constantes de comportamento da interface (spec 3.4, 12.2).
abstract final class AppConstants {
  /// Tempo sem interacao antes de ocultar os controles do player.
  static const controlsAutoHide = Duration(seconds: 4);

  /// Retrocesso/avanco padrao dos botoes e setas.
  static const seekStep = Duration(seconds: 10);

  /// Transicoes rapidas de UI (150-250 ms).
  static const shortTransition = Duration(milliseconds: 200);

  /// Area minima de toque no desktop.
  static const minTouchTarget = 44.0;

  /// Margem lateral minima anti-overscan no modo TV.
  static const tvMinMargin = 32.0;

  /// Velocidades do menu do player (spec 13).
  static const speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  /// Limite de itens em "Continuar assistindo".
  static const continueWatchingLimit = 10;

  /// Versao exibida no diagnostico. Manual de proposito (sem
  /// package_info para nao puxar dependencia nativa): sincronizar com
  /// o `version:` do pubspec.yaml a cada release.
  static const appVersion = '0.1.0-rc.6';

  /// Tamanho maximo de um manifesto JSON (colado, arquivo ou URL).
  static const maxManifestBytes = 256 * 1024;

  /// Timeout de rede para buscar manifesto/repositorio.
  static const addonFetchTimeout = Duration(seconds: 15);

  /// Carga sem sinal de vida alem disso vira erro recuperavel (spec 26).
  static const loadTimeout = Duration(seconds: 30);

  /// Buffer continuo alem disso vira erro recuperavel (spec 26).
  static const bufferTimeout = Duration(seconds: 15);
}
