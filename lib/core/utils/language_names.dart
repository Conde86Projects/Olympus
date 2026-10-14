import 'package:player/models/playback_state.dart';

/// Nome de exibicao em pt-BR para um codigo de idioma de faixa (spec
/// 26.12: o idioma de cada faixa aparece claramente, e a falta do
/// preferido e informada como "sem faixa em <nome>"). Aceita ISO 639-1,
/// 639-2 e variantes com regiao ("pt-BR"). Codigo desconhecido volta
/// como esta, nunca em branco: exibir o codigo cru e melhor que omitir.
String languageDisplayName(String code) {
  final normalized = code.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  return _names[normalized] ?? code.trim();
}

/// Id da primeira faixa no idioma preferido, ou null. Casa primeiro
/// pelo codigo da faixa e depois pelo rotulo, sem diferenciar maiusculas.
/// Sem preferencia (null/vazio), devolve null: quem chama mantem o
/// padrao do player. Usado na abertura (player_screen) e no aviso do
/// submenu (player_settings_panel).
String? findTrackForLanguage(List<MediaTrack> tracks, String? preferred) {
  final want = preferred?.trim().toLowerCase();
  if (want == null || want.isEmpty) return null;
  for (final track in tracks) {
    if (track.language?.toLowerCase() == want) return track.id;
  }
  for (final track in tracks) {
    if (track.label.toLowerCase() == want) return track.id;
  }
  return null;
}

/// Códigos primários (um por idioma) para o seletor de idioma
/// preferido — mesma base dos rótulos acima. Sem campo de texto: na
/// TV física o IME come as setas com o campo focado e o D-pad prende
/// (o DpadFieldExit não recebe o evento); a lista navegável não
/// prende nunca. Ordem alfabética pelo rótulo em pt-BR.
const languagePickerCodes = [
  'deu', // alemão
  'ara', // árabe
  'zho', // chinês
  'kor', // coreano
  'dan', // dinamarquês
  'spa', // espanhol
  'fin', // finlandês
  'fra', // francês
  'ell', // grego
  'heb', // hebraico
  'hin', // hindi
  'nld', // holandês
  'ind', // indonésio
  'eng', // inglês
  'ita', // italiano
  'jpn', // japonês
  'msa', // malaio
  'nor', // norueguês
  'pol', // polonês
  'por', // português
  'rus', // russo
  'swe', // sueco
  'tha', // tailandês
  'tur', // turco
  'vie', // vietnamita
  'und', // indefinido
];

const _names = {
  'por': 'português',
  'pt': 'português',
  'eng': 'inglês',
  'en': 'inglês',
  'spa': 'espanhol',
  'es': 'espanhol',
  'fra': 'francês',
  'fre': 'francês',
  'fr': 'francês',
  'deu': 'alemão',
  'ger': 'alemão',
  'de': 'alemão',
  'ita': 'italiano',
  'it': 'italiano',
  'jpn': 'japonês',
  'ja': 'japonês',
  'kor': 'coreano',
  'ko': 'coreano',
  'zho': 'chinês',
  'chi': 'chinês',
  'zh': 'chinês',
  'rus': 'russo',
  'ru': 'russo',
  'ara': 'árabe',
  'ar': 'árabe',
  'hin': 'hindi',
  'hi': 'hindi',
  'nld': 'holandês',
  'dut': 'holandês',
  'nl': 'holandês',
  'pol': 'polonês',
  'pl': 'polonês',
  'tur': 'turco',
  'tr': 'turco',
  'swe': 'sueco',
  'sv': 'sueco',
  'nor': 'norueguês',
  'no': 'norueguês',
  'dan': 'dinamarquês',
  'da': 'dinamarquês',
  'fin': 'finlandês',
  'fi': 'finlandês',
  'ell': 'grego',
  'gre': 'grego',
  'el': 'grego',
  'heb': 'hebraico',
  'he': 'hebraico',
  'tha': 'tailandês',
  'th': 'tailandês',
  'vie': 'vietnamita',
  'vi': 'vietnamita',
  'ind': 'indonésio',
  'id': 'indonésio',
  'msa': 'malaio',
  'may': 'malaio',
  'ms': 'malaio',
  'und': 'indefinido',
};
