import 'package:flutter/services.dart';

/// Acoes do player cuja tecla o usuario pode trocar. Espaco, Enter, Esc,
/// as setas e Tab ficam fixos (navegacao basica) e nao entram aqui.
enum ShortcutAction {
  mute('Mudo'),
  fullscreen('Tela cheia'),
  info('Informações do vídeo'),
  subtitles('Legendas'),
  audio('Áudio'),
  cinema('Modo cinema'),
  closePlayer('Fechar player');

  const ShortcutAction(this.label);
  final String label;

  /// Tecla padrao da acao.
  LogicalKeyboardKey get defaultKey => switch (this) {
        mute => LogicalKeyboardKey.keyM,
        fullscreen => LogicalKeyboardKey.keyF,
        info => LogicalKeyboardKey.keyI,
        subtitles => LogicalKeyboardKey.keyS,
        audio => LogicalKeyboardKey.keyA,
        cinema => LogicalKeyboardKey.keyC,
        closePlayer => LogicalKeyboardKey.keyQ,
      };
}

/// Teclas que o usuario nao pode atribuir: garantem a navegacao basica.
final Set<LogicalKeyboardKey> reservedShortcutKeys = {
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.tab,
};

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// Se a tecla pode virar atalho (nao reservada e nao modificadora).
bool isAssignableShortcutKey(LogicalKeyboardKey key) =>
    !reservedShortcutKeys.contains(key) &&
    !_modifierKeys.contains(key) &&
    key.keyLabel.isNotEmpty;

/// Nome da tecla para mostrar na tela.
String shortcutKeyLabel(LogicalKeyboardKey key) => key.keyLabel.length == 1
    ? key.keyLabel.toUpperCase()
    : key.keyLabel;

/// Teclas salvas (`acao -> id da tecla`). Descarta nomes desconhecidos,
/// valores que nao sao inteiros, teclas reservadas ou invalidas e
/// conflitos (tecla ja efetiva em outra acao): cai no padrao.
Map<ShortcutAction, LogicalKeyboardKey> shortcutsFrom(Object? raw) {
  if (raw is! Map) return const {};
  final result = <ShortcutAction, LogicalKeyboardKey>{};
  for (final action in ShortcutAction.values) {
    final id = raw[action.name];
    if (id is! int) continue;
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    if (key == null || !isAssignableShortcutKey(key)) continue;
    result[action] = key;
  }
  for (final action in result.keys.toList()) {
    final key = result[action]!;
    final clash = ShortcutAction.values
        .any((o) => o != action && (result[o] ?? o.defaultKey) == key);
    if (clash) result.remove(action);
  }
  return result;
}
