import 'package:flutter/services.dart';

import 'shortcut_action.dart';

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
    this.subtitleSize = SubtitleSize.medium,
    this.subtitleColor = SubtitleColor.white,
    this.subtitlePosition = SubtitlePosition.normal,
    this.subtitleBackground = true,
    this.initialVolume = 1.0,
    this.animations = true,
    this.alwaysOnTop = false,
    this.startInFullscreen = false,
    this.restoreWindowGeometry = true,
    this.showOnboarding = true,
    this.language = 'pt-BR',
    this.tvMode = false,
    this.tvModeAuto = true,
    this.compatibleVideoOutput = false,
    this.librarySort = LibrarySort.recent,
    this.textSize = TextSizeOption.normal,
    this.hiddenDestinations = const [],
    this.shortcuts = const {},
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

  /// Aparencia da legenda (F6, U01).
  final SubtitleSize subtitleSize;
  final SubtitleColor subtitleColor;
  final SubtitlePosition subtitlePosition;
  final bool subtitleBackground;

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

  /// Android: desliga a saida direta do decodificador (MediaCodec) e usa
  /// o caminho compativel do media_kit (`vo=gpu`). Escape para TVs com
  /// decodificador defeituoso; vale ao reabrir o app.
  final bool compatibleVideoOutput;

  /// Ordem da lista da Biblioteca; lembrada entre aberturas.
  final LibrarySort librarySort;

  /// Tamanho do texto do app inteiro (nao inclui a legenda desenhada).
  final TextSizeOption textSize;

  /// Destinos do menu principal que o usuario escondeu. Padrao: nenhum.
  /// Inicio e Configuracoes nao existem em [MainDestination]: nunca saem.
  final List<MainDestination> hiddenDestinations;

  /// Teclas escolhidas para os atalhos do player. Acao ausente usa o
  /// padrao ([ShortcutAction.defaultKey]).
  final Map<ShortcutAction, LogicalKeyboardKey> shortcuts;

  /// Tecla efetiva da [action]: a escolhida ou a padrao.
  LogicalKeyboardKey keyFor(ShortcutAction action) =>
      shortcuts[action] ?? action.defaultKey;

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
    SubtitleSize? subtitleSize,
    SubtitleColor? subtitleColor,
    SubtitlePosition? subtitlePosition,
    bool? subtitleBackground,
    double? initialVolume,
    bool? animations,
    bool? alwaysOnTop,
    bool? startInFullscreen,
    bool? restoreWindowGeometry,
    bool? showOnboarding,
    String? language,
    bool? tvMode,
    bool? tvModeAuto,
    bool? compatibleVideoOutput,
    LibrarySort? librarySort,
    TextSizeOption? textSize,
    List<MainDestination>? hiddenDestinations,
    Map<ShortcutAction, LogicalKeyboardKey>? shortcuts,
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
      subtitleSize: subtitleSize ?? this.subtitleSize,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      subtitlePosition: subtitlePosition ?? this.subtitlePosition,
      subtitleBackground: subtitleBackground ?? this.subtitleBackground,
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
      compatibleVideoOutput:
          compatibleVideoOutput ?? this.compatibleVideoOutput,
      librarySort: librarySort ?? this.librarySort,
      textSize: textSize ?? this.textSize,
      hiddenDestinations: hiddenDestinations ?? this.hiddenDestinations,
      shortcuts: shortcuts ?? this.shortcuts,
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
        'subtitleSize': subtitleSize.name,
        'subtitleColor': subtitleColor.name,
        'subtitlePosition': subtitlePosition.name,
        'subtitleBackground': subtitleBackground,
        'initialVolume': initialVolume,
        'animations': animations,
        'alwaysOnTop': alwaysOnTop,
        'startInFullscreen': startInFullscreen,
        'restoreWindowGeometry': restoreWindowGeometry,
        'showOnboarding': showOnboarding,
        'language': language,
        'tvMode': tvMode,
        'tvModeAuto': tvModeAuto,
        'compatibleVideoOutput': compatibleVideoOutput,
        'librarySort': librarySort.name,
        'textSize': textSize.name,
        'hiddenDestinations': [for (final d in hiddenDestinations) d.name],
        'shortcuts': {
          for (final e in shortcuts.entries) e.key.name: e.value.keyId,
        },
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
      subtitleSize: _byName(
          SubtitleSize.values, map['subtitleSize'], SubtitleSize.medium),
      subtitleColor: _byName(
          SubtitleColor.values, map['subtitleColor'], SubtitleColor.white),
      subtitlePosition: _byName(SubtitlePosition.values,
          map['subtitlePosition'], SubtitlePosition.normal),
      subtitleBackground: (map['subtitleBackground'] ?? true) as bool,
      initialVolume: ((map['initialVolume'] ?? 1.0) as num).toDouble(),
      animations: (map['animations'] ?? true) as bool,
      alwaysOnTop: (map['alwaysOnTop'] ?? false) as bool,
      startInFullscreen: (map['startInFullscreen'] ?? false) as bool,
      restoreWindowGeometry: (map['restoreWindowGeometry'] ?? true) as bool,
      showOnboarding: (map['showOnboarding'] ?? true) as bool,
      language: (map['language'] ?? 'pt-BR') as String,
      tvMode: (map['tvMode'] ?? false) as bool,
      tvModeAuto: (map['tvModeAuto'] ?? true) as bool,
      compatibleVideoOutput:
          (map['compatibleVideoOutput'] ?? false) as bool,
      librarySort: _byName(
          LibrarySort.values, map['librarySort'], LibrarySort.recent),
      textSize: _byName(
          TextSizeOption.values, map['textSize'], TextSizeOption.normal),
      hiddenDestinations: _destinationsFrom(map['hiddenDestinations']),
      shortcuts: shortcutsFrom(map['shortcuts']),
      windowX: (map['windowX'] as num?)?.toDouble(),
      windowY: (map['windowY'] as num?)?.toDouble(),
      windowWidth: (map['windowWidth'] as num?)?.toDouble(),
      windowHeight: (map['windowHeight'] as num?)?.toDouble(),
    );
  }
}

enum AppThemeMode { dark, system }

enum SubtitleSize { small, medium, large }

enum SubtitleColor { white, yellow, cyan }

enum SubtitlePosition { low, normal, high }

/// Ordem da Biblioteca: último adicionado primeiro, título de A a Z ou
/// os vídeos mais longos primeiro.
enum LibrarySort { recent, title, duration }

/// Tamanho do texto do app: multiplica o texto do sistema por 1,0, 1,15
/// ou 1,3.
enum TextSizeOption {
  normal(1.0, 'Normal'),
  large(1.15, 'Grande'),
  larger(1.3, 'Maior');

  const TextSizeOption(this.scale, this.label);
  final double scale;
  final String label;
}

/// Destinos do menu principal que podem ser escondidos.
enum MainDestination {
  library('Biblioteca'),
  favorites('Favoritos'),
  addons('Add-ons'),
  history('Histórico');

  const MainDestination(this.label);
  final String label;
}

/// Lista salva de destinos escondidos: ignora nomes desconhecidos,
/// repetidos e qualquer valor que nao seja lista.
List<MainDestination> _destinationsFrom(Object? raw) {
  if (raw is! List) return const [];
  final result = <MainDestination>[];
  for (final name in raw) {
    for (final d in MainDestination.values) {
      if (d.name == name && !result.contains(d)) result.add(d);
    }
  }
  return result;
}

/// Valor salvo desconhecido (versao futura ou dado corrompido) cai no padrao.
T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
