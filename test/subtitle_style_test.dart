import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/subtitle_style.dart';

void main() {
  test('padrao: branco, fundo semitransparente, tamanho normal, embaixo', () {
    expect(SubtitleStyle.defaults.toMpvProperties(), {
      'sub-font-size': '55',
      'sub-color': '#FFFFFFFF',
      'sub-back-color': '#80000000',
      'sub-pos': '100',
    });
  });

  test('valores trocados aparecem nas propriedades do mpv', () {
    const style = SubtitleStyle(
      fontSize: 70,
      textColor: 'FFFFFF00',
      backColor: '00000000',
      position: 85,
    );
    expect(style.toMpvProperties(), {
      'sub-font-size': '70',
      'sub-color': '#FFFFFF00',
      'sub-back-color': '#00000000',
      'sub-pos': '85',
    });
  });
}
