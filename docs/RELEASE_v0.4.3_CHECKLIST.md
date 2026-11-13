# Release Checklist — v0.4.3

Versão `0.4.3+1015`. Formulário de repositório na TV, repositório confiável na rede
local e as correções das auditorias depois da 0.4.2.

- [x] `flutter analyze` limpo e 1193 testes passando
- [x] TCL (versionName `0.4.3`, dumpsys): a seta para baixo para em "Nome" com o anel azul,
  sem teclado; OK abre o teclado da TV; a legenda de "Confiável" fala da rede local
- [x] TCL: o app abre e reproduz vídeo, sem erro no logcat
- [x] pacote do Windows abre pelo zip e fica vivo; versão `0.4.3+1015` no `player.exe`, sem a DLL do cofre
- [x] repositório confiável na rede local e não confiável recusado (testes automáticos, com
  o baixador de verdade num servidor local)

## Limites conhecidos

- Repositório em rede local só foi conferido por teste automático: não digitei um endereço
  real na TV (o teclado da TV é lento por tecla).
- Add-on instalado de repositório da rede local não herda a permissão: o catálogo e os
  vídeos dele em endereço interno seguem recusados.
- A miniatura de vídeo novo (Kotlin, quadro em thread própria) só foi conferida compilando
  e abrindo vídeos que já tinham miniatura; o primeiro quadro de um arquivo novo não foi
  visto no aparelho.
- O menu do cartão aberto pela tecla de menu na TV continua sem item destacado até a
  primeira seta.
- O bloqueio de rede interna não enxerga redirecionamento (ver 0.4.2).
- Os testes à mão da v0.4.0 seguem pendentes (seletor de arquivos do Windows, monitor de
  34", celular físico).

## SHA-256

- `Olympus-0.4.3.apk`: `d169758da01e6cac86fff673f31009c512eb91dad0c9ea06233ea3498f229d4a`
- `Olympus-0.4.3-windows.zip`: `916b15cbfd13b3d41a4470a4f0f808acfecafbcceb584220371f57033deb0b5c`
