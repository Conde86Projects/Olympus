# Release Checklist — v0.3.4

Versão publicada em 01/11/2026, `0.3.4+1010`.

- [x] `flutter analyze` limpo e 835 testes passando
- [x] versionName `0.3.4` na TCL e no emulador (`dumpsys`); o app abre nos dois
- [x] pacote do Windows abre pelo zip; versão `0.3.4+1010` no `player.exe`
- [x] busca sem diferenciar maiúsculas: emulador e Windows
- [x] busca sem resultado mostra "Nada encontrado" e "Limpar busca": Windows
- [x] ordem por título e por recentes: TCL, emulador e Windows
- [x] ordem escolhida lembrada ao reabrir o app: emulador e Windows
- [x] TCL: subir ao campo não abre o teclado; OK abre; digitar filtra; buscar no teclado leva o foco ao primeiro vídeo
- [x] TCL: seta para a direita vai do campo ao seletor de ordem e a esquerda volta
- [x] Tab no Windows passa pelo campo e segue para a lista

## Limites conhecidos

- A busca ignora acentos só nas letras acentuadas do português (á à â ã ä å é è ê
  ë í ì î ï ó ò ô õ ö ú ù û ü ç ñ); outros alfabetos comparam como estão.
- Duração ordena os mais longos primeiro; vídeos sem duração conhecida ficam por último.
- Os limites da v0.3.3 seguem valendo: legenda ao lado no celular depende do acesso
  do Android à pasta, o seletor do sistema pausa o vídeo, e duas legendas de pastas
  diferentes com o mesmo nome ficam iguais na lista.

## SHA-256

- `Olympus-0.3.4.apk`: `3a5d193ef9a512132b2f0cc85383aaa93b85ee7ee644612a285b0714fb5e40cc`
- `Olympus-0.3.4-windows.zip`: `171c7843efac17a62d096b17e35c531b1d23beea81dc8b23ed2a29d082585723`
