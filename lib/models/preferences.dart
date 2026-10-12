/// Preferencias do usuario (spec 5.3, 16). Imutavel.
class UserPreferences {
  const UserPreferences({
    this.theme = AppThemeMode.dark,
    this.autoplay = false,
    this.autoplayNext = false,
    this.rememberPosition = true,
    this.resumeAutomatically = true,
    this.defaultSpeed = 1.0,
    this.defaultSubtitle,
    this.defaultAudio,
    this.subtitlesByDefault = false,
    this.initialVolume = 1.0,
    this.animations = true,
    this.alwaysOnTop = false,
    this.startInFullscreen = false,
    this.restoreWindowGeometry = true,
    this.showOnboarding = true,
    this.language = 'pt-BR',
    this.tvMode = false,
    this.tvModeAuto = true,
    this.windowX,
    this.windowY,
    this.windowWidth,
    this.windowHeight,
  });

  final AppThemeMode theme;

  /// Inicia a reproducao sozinho ao abrir uma midia (spec 16). Desligado
  /// por padrao: sem preferencia explicita, aguarda o usuario (spec 7).
  final bool autoplay;
  final bool autoplayNext;
  final bool rememberPosition;

  /// Ao abrir um item com posicao salva, volta a ela sozinho. Com
  /// [rememberPosition] desligado nao ha posicao salva e nada acontece.
  final bool resumeAutomatically;
  final double defaultSpeed;

  /// Idioma preferido de legenda/audio (ex. "por", "eng"): na abertura,
  /// seleciona a primeira faixa com esse idioma. Vazio = padrao do player
  /// (audio) ou [subtitlesByDefault] (legenda).
  final String? defaultSubtitle;
  final String? defaultAudio;

  /// Liga legendas por padrao na abertura (spec 16). Desligado por padrao.
  final bool subtitlesByDefault;

  /// Volume aplicado a cada abertura (0.0-1.0).
  final double initialVolume;

  /// Transicoes de tela e do painel do player.
  final bool animations;
  final bool alwaysOnTop;
  final bool startInFullscreen;

  /// Restaura tamanho e posicao da janela anterior (spec 14.1).
  final bool restoreWindowGeometry;
  final bool showOnboarding;
  final String language;

  /// Modo TV (Fase 4, spec 3.4/12.2): alvos maiores, texto maior,
  /// margem anti-overscan e controles persistentes navegando.
  final bool tvMode;

  /// Quando true (padrão), o arranque aplica a detecção Leanback em
  /// [tvMode]. Mexer no interruptor manual desliga o automático para
  /// a escolha do usuário valer.
  final bool tvModeAuto;

  /// Geometria salva da janela (spec 14.1). Null = primeira execucao.
  final double? windowX;
  final double? windowY;
  final double? windowWidth;
  final double? windowHeight;

  UserPreferences copyWith({
    AppThemeMode? theme,
    bool? autoplay,
    bool? autoplayNext,
    bool? rememberPosition,
    bool? resumeAutomatically,
    double? defaultSpeed,
    String? Function()? defaultSubtitle,
    String? Function()? defaultAudio,
    bool? subtitlesByDefault,
    double? initialVolume,
    bool? animations,
    bool? alwaysOnTop,
    bool? startInFullscreen,
    bool? restoreWindowGeometry,
    bool? showOnboarding,
    String? language,
    bool? tvMode,
    bool? tvModeAuto,
    double? Function()? windowX,
    double? Function()? windowY,
    double? Function()? windowWidth,
    double? Function()? windowHeight,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      autoplay: autoplay ?? this.autoplay,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      rememberPosition: rememberPosition ?? this.rememberPosition,
      resumeAutomatically: resumeAutomatically ?? this.resumeAutomatically,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultSubtitle:
          defaultSubtitle != null ? defaultSubtitle() : this.defaultSubtitle,
      defaultAudio: defaultAudio != null ? defaultAudio() : this.defaultAudio,
      subtitlesByDefault: subtitlesByDefault ?? this.subtitlesByDefault,
      initialVolume: initialVolume ?? this.initialVolume,
      animations: animations ?? this.animations,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      startInFullscreen: startInFullscreen ?? this.startInFullscreen,
      restoreWindowGeometry:
          restoreWindowGeometry ?? this.restoreWindowGeometry,
      showOnboarding: showOnboarding ?? this.showOnboarding,
      language: language ?? this.language,
      tvMode: tvMode ?? this.tvMode,
      tvModeAuto: tvModeAuto ?? this.tvModeAuto,
      windowX: windowX != null ? windowX() : this.windowX,
      windowY: windowY != null ? windowY() : this.windowY,
      windowWidth:
          windowWidth != null ? windowWidth() : this.windowWidth,
      windowHeight:
          windowHeight != null ? windowHeight() : this.windowHeight,
    );
  }

  Map<String, Object?> toMap() => {
        'theme': theme.name,
        'autoplay': autoplay,
        'autoplayNext': autoplayNext,
        'rememberPosition': rememberPosition,
        'resumeAutomatically': resumeAutomatically,
        'defaultSpeed': defaultSpeed,
        'defaultSubtitle': defaultSubtitle,
        'defaultAudio': defaultAudio,
        'subtitlesByDefault': subtitlesByDefault,
        'initialVolume': initialVolume,
        'animations': animations,
        'alwaysOnTop': alwaysOnTop,
        'startInFullscreen': startInFullscreen,
        'restoreWindowGeometry': restoreWindowGeometry,
        'showOnboarding': showOnboarding,
        'language': language,
        'tvMode': tvMode,
        'tvModeAuto': tvModeAuto,
        'windowX': windowX,
        'windowY': windowY,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
      };

  factory UserPreferences.fromMap(Map<String, Object?> map) {
    return UserPreferences(
      theme: AppThemeMode.values.byName((map['theme'] ?? 'dark') as String),
      autoplay: (map['autoplay'] ?? false) as bool,
      autoplayNext: (map['autoplayNext'] ?? false) as bool,
      rememberPosition: (map['rememberPosition'] ?? true) as bool,
      resumeAutomatically: (map['resumeAutomatically'] ?? true) as bool,
      defaultSpeed: ((map['defaultSpeed'] ?? 1.0) as num).toDouble(),
      defaultSubtitle: map['defaultSubtitle'] as String?,
      defaultAudio: map['defaultAudio'] as String?,
      subtitlesByDefault: (map['subtitlesByDefault'] ?? false) as bool,
      initialVolume: ((map['initialVolume'] ?? 1.0) as num).toDouble(),
      animations: (map['animations'] ?? true) as bool,
      alwaysOnTop: (map['alwaysOnTop'] ?? false) as bool,
      startInFullscreen: (map['startInFullscreen'] ?? false) as bool,
      restoreWindowGeometry: (map['restoreWindowGeometry'] ?? true) as bool,
      showOnboarding: (map['showOnboarding'] ?? true) as bool,
      language: (map['language'] ?? 'pt-BR') as String,
      tvMode: (map['tvMode'] ?? false) as bool,
      tvModeAuto: (map['tvModeAuto'] ?? true) as bool,
      windowX: (map['windowX'] as num?)?.toDouble(),
      windowY: (map['windowY'] as num?)?.toDouble(),
      windowWidth: (map['windowWidth'] as num?)?.toDouble(),
      windowHeight: (map['windowHeight'] as num?)?.toDouble(),
    );
  }
}

enum AppThemeMode { dark, system }
