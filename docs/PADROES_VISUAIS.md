# Padrões visuais do Olympus

Referência única de visual para **TV, desktop (Windows) e celular**.
Regra: um componente tem **um** desenho; o que muda entre plataformas
é só tamanho/densidade (tokens), nunca o estilo. Antes de criar um
componente novo, use o daqui; se precisar de um novo padrão, registre
aqui no mesmo commit.

Atualizado em 01/11/2026.

## Cores (`PlayerTheme`)

| Token | Cor | Uso |
|---|---|---|
| `background` | `#0E0E10` | fundo das telas |
| `surface` | `#242426` a 70% | cartões, painéis |
| `primaryText` | `#F2F2F3` | texto principal, ícones |
| `secondaryText` | `#B8B8BE` | texto auxiliar, estados desligados |
| `accent` | `#4C8DFF` | destaque, foco, ligado, progresso |
| `error` | `#D06060` | erros |
| `success` | `#5FA86B` | sucesso pontual |

Tema escuro sempre. Nada de verde-água/roxo do Material padrão: tudo
que for "selecionado" usa `accent`.

## Interruptor (switch)

- **Um só desenho em todas as plataformas:** o clássico de trilho fino
  (33x14, dedão 20), aprovado na TV. O Switch do Material 3 (52x32,
  trilho azul cheio) **não** é usado.
- Ligado: dedão `accent`, trilho `accent` a 40%. Desligado: dedão
  `secondaryText`, trilho branco a 15%.
- Como usar: envolver a linha com `AppSwitchTheme`
  (`lib/widgets/app_switch_theme.dart`); nas Configurações a seção já
  faz isso para toda linha com interruptor.
- Teste que fixa: `test/app_switch_test.dart` (desktop, celular e TV).

## Cartão de fileira (Início)

- `MediaPosterCard` (`lib/widgets/media_card.dart`): imagem com raio 12 e
  título + detalhe embaixo, numa linha cada.
- Proporção: 16:9 para quadro de vídeo (miniatura local é paisagem, e
  cortar em 2:3 borraria) e 2:3 para pôster de catálogo.
- Largura pela janela: quadro em `janela / 6`, preso entre 240 e 360;
  pôster em `janela / 8`, preso entre 160 e 240. Janela maior mostra mais
  cartões, não cartões maiores.
- Foco: borda `accent` de 3 px. Mouse em cima: borda branca a 24%.
  Parado: branca a 8%.
- Setas andam de cartão em cartão. O menu abre pelo botão, pelo clique
  direito e pela tecla de menu. Na TV, a seta para baixo chega ao botão
  do menu, porque nem todo controle tem tecla de menu.
- Na TV, o primeiro voltar leva às ações do topo, e o seguinte sai do app.
- Fileira de add-on: nome da fonte, "Ver tudo" e "Atualizar" no topo.
  Carregando: barra de progresso no lugar dos cartões, sem pular a tela.
  Falha: motivo e "Tentar de novo" só naquela fileira. Erro salvo de uma
  sessão anterior tenta sozinho uma vez ao abrir o app.
- Testes: `test/home_desktop_test.dart`, `test/home_addon_rows_test.dart`.

## Avisos (toast)

- `showAppToast(context, mensagem, error: false)`
  (`lib/widgets/app_toast.dart`). **Nunca** `ScaffoldMessenger`/
  `SnackBar` direto.
- Cartão escuro (`#242428` a 95%), raio 14, borda branca a 8%, sombra
  8, largura até 440 (menos 32 de margem em telas estreitas),
  centralizado **no topo**, abaixo da barra de status.
- Ícone: `check_circle_outline` em `accent` (sucesso/informação) ou
  `error_outline` em `error`.
- Movimento: cai do topo com leve quique (520 ms, `easeOutBack`), fica
  4 s, sobe acelerando (320 ms, `easeInCubic`). Não bloqueia toque nem
  foco; um aviso novo substitui o anterior.
- Teste: `test/app_toast_test.dart`.

## Alvos de toque e tamanhos

| Plataforma | Alvo mínimo | Observação |
|---|---|---|
| Desktop | 44 | `TvLayout.minTarget` |
| Celular | 48 dp | `MobileMode.minTouchTarget` |
| TV | tokens por classe (44/44/52) | `TvLayoutTokens.controlHeight` |

Botões do player: `RoundPlayerButton`. Card de uma fileira em altura
abaixo de 420 (janela pequena e celular deitado).

## Player

- Botões dos cantos sobre o vídeo: fundo preto a 45%
  (`overVideo: true`) para aparecer sobre imagem clara.
- Card de controles: fosco (`BackdropFilter`), preto a 68%, raio 16.
- Reposicionamento (retomada/troca de qualidade HLS): cobertura preta
  "Ajustando a posição…" até o vídeo andar no ponto salvo.
- Barra some após ~4 s sem interação em todas as plataformas; na TV,
  com a barra visível, o primeiro BACK só a esconde.

## Painéis e menus

- Painel de configurações do player ancorado na engrenagem; com pouco
  espaço acima (< 480), ganha teto e rola.
- Menus da TV: tema compacto `PlayerTheme.tvMenus` (só no modo TV).
- Navegação inferior do celular: aba ativa com indicador `accent` a
  35%.
- Foco visível sempre (anel `accent`); na TV, espessura pelos tokens.

## Movimento

- Transições de tela: `FadeUpwardsPageTransitionsBuilder`, ou nenhuma
  com "Animações" desligado nas Configurações.
- Barras de progresso: o indicador linear padrão em `accent`.
