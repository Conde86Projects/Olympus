# Validação no Windows (janela pequena, compacto, minimizar)

Assistir numa janela pequena, sempre no topo, enquanto se faz outra
coisa é a ideia central do produto. Esta rodada cobre a tabela "Tela"
de `VALIDACAO_APARELHOS.md` nas linhas do Windows.

## Ambiente (18/10/2026)

- Windows 11 Pro, monitor 3440x1440 a 125% (120 dpi).
- Build debug (`flutter build windows --debug`), Flutter 3.47.7.
- Vídeo local AVI 608x336 (biblioteca do PC de testes).
- Janela dirigida por Win32 (`SetWindowPos`, `ShowWindow`) e
  capturada com `PrintWindow`; tamanhos abaixo em pixels lógicos.

## Resultados

| Caso | Resultado |
|---|---|
| Janela 1920x1080 | OK. Desktop igual ao anterior: card de 880 com título, volume e progresso. |
| Janela 480x270 (mínimo) | OK após correção. Player com card de uma fileira; início rola. |
| Modo compacto | OK após correção. Abre em 480x270, sempre no topo; sair volta ao tamanho anterior e ao topo da preferência. |
| Minimizar e restaurar (compacto, no topo) | OK após correção. Posição gravada ao minimizar (1:16); o vídeo seguiu (1:27 ao restaurar); topo mantido. |
| Ultrawide maximizado (3440x1440) | OK. Menus centralizados em 1080; vídeo com barras laterais; card centralizado. |

## O que estava errado e foi corrigido

- **Mínimo da janela 800x600.** O Windows prendia o compacto
  (480x270) e o arrasto nesse piso. Agora o mínimo é o tamanho do
  compacto (`WindowManagerService.minimumSize`). A geometria salva
  aceita esse mínimo.
- **Card do player grande demais em janela baixa.** Abaixo de 420 de
  altura o card normal (194 de altura) cobria metade do vídeo e
  encostava nos botões dos cantos. Agora há um card de uma fileira:
  mudo, ±10 s, play, tempo (fonte 12), progresso e configurações, com
  botões de 36. Os cantos também ficam em 36. Sem título. Acima de 420
  nada muda.
- **Menus estouravam em janela baixa** (faixas amarelas e pretas no
  estado vazio e na apresentação). Agora rolam (`ScrollWhenShort`).
  Com espaço de sobra o desenho continua o mesmo.
- **Minimizar não gravava a posição.** Só a saída do player gravava;
  encerrar o app minimizado perdia a retomada. O minimizar do
  `window_manager` (`WindowService.minimized`) e o ciclo de vida
  `hidden`/`paused` agora gravam sem pausar. No Windows o Flutter não
  entrega `hidden` ao minimizar com o `window_manager` instalado, por
  isso o aviso vem do plugin.
- **Tela vermelha ao fechar o player depois do compacto.** Trocar o
  card com o foco dentro dele fazia o `SliderFocusRing` novo subir os
  ancestrais de um elemento em desativação. Agora a primeira checagem
  roda depois do frame.

## Testes

`test/small_window_test.dart` cobre os menus em 464x231 (área cliente
do compacto) sem estouro, o card de uma fileira (altura, botões de 36,
nada fora da tela, progresso com largura útil), o painel de
configurações, o card de desktop intacto a partir de 420 de altura,
minimizar gravando a posição e a sequência compacto → minimizar → sair
→ fechar sem erro.

## Pendências

- Fechar a janela pelo X do Windows com o player aberto ainda não
  grava a posição (não há `setPreventClose`). Fica para outra rodada.
- Não testado num monitor 1080p de verdade nem em 100%/150% de escala.
