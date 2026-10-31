/// Estilo das legendas (F6, U01). Os valores sao convertidos nas
/// propriedades `sub-*` do mpv; cores no formato `AARRGGBB` (hexadecimal
/// sem `#`, o `#` e acrescentado aqui).
class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize = 55,
    this.textColor = 'FFFFFFFF',
    this.backColor = '80000000',
    this.position = 100,
  });

  /// Padrao do projeto: texto branco, fundo preto semitransparente,
  /// tamanho normal do mpv, embaixo da tela.
  static const defaults = SubtitleStyle();

  /// Tamanho em pontos do mpv (padrao do mpv: 55).
  final int fontSize;

  /// Cor do texto em `AARRGGBB`.
  final String textColor;

  /// Cor do fundo da legenda em `AARRGGBB`; `00000000` sem fundo.
  final String backColor;

  /// Posicao vertical de 0 (topo) a 100 (base da tela).
  final int position;

  Map<String, String> toMpvProperties() => {
        'sub-font-size': '$fontSize',
        'sub-color': '#$textColor',
        'sub-back-color': '#$backColor',
        'sub-pos': '$position',
      };
}
