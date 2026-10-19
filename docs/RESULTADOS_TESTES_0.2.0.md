# Resultados — pacote de testes finais (0.2.0, sem tag)

Execução de `docs/TESTES_FINAIS_0.2.0.md` em 18–19/10/2026.
Celular físico, Windows e TCL executados. **Única pendência:** o
catálogo na TCL (o feed temporário voltou a responder 502 no meio da
rodada; o caso "fonte fora do ar" ficou coberto ali). Sem tag
`v0.2.0`; `v0.1.0` intacta em `bd3270a`.

## Versão testada

| Item | Valor |
|---|---|
| Árvore | cópia limpa (worktree) sem as alterações locais de vídeo Android/TV e menus da TV |
| Commit inicial | `e79d466` → bloqueado (catálogo não estava commitado) |
| Commit do catálogo | `95590f0` (separado das alterações locais da outra sessão) |
| Commit testado | `a1f6de6` (correção do X do Windows achada nesta rodada) |
| `pubspec` / `AppConstants` | `0.1.0+9` / `0.1.0` (sem bump; o bump fica para o marco) |
| `dart analyze` | limpo |
| `flutter test` | 614/614 |
| APK (debug) SHA-256 | `d9026589172c9f55573c941e5a42dd32ef732df9e143ea7428f295e4d54311e3` |
| Windows | build release do mesmo commit |
| Celular | APK debug de `08b6633` + correção do painel (problema 5, depois commitada em `75a02f9`); catálogo com APK debug de `683f847` |
| Rodada 2 (19/10) | `683f847` (catálogo no Windows e no celular), `ff3c455` (saída direta) e `a9984aa` (correções da TCL) |
| TCL final | APK **release** de `ff3c455` + `a9984aa` (SHA-256 `67dbed16...`), TV reiniciada |

## Gates

- [x] Árvore limpa no commit testado (`a1f6de6`).
- [x] `flutter test` verde: 614.
- [x] `dart analyze` limpo.
- [ ] Feed temporário respondendo — **FALHA**: HTTP 502 desde
      ~21:00 (três tentativas). O stream do Mux responde (200).
- [x] Instalação com serial explícito (TCL `192.168.1.4:5555`).

## Problemas encontrados

1. **Catálogo ausente em `e79d466`** — o adaptador do feed próprio,
   a tela do catálogo, a rota, o botão "Abrir catálogo" e o registro
   no `main.dart` eram alterações locais nunca commitadas; o feed era
   recusado ("O endereço não é um manifesto nem um feed de catálogo
   válido"). **Corrigido** em `95590f0` (só o catálogo, 614 testes).
   Captura: `testes-0.2.0/windows-catalogo-ausente-e79d466.png`.
2. **Feed temporário fora do ar** — `.../feed.json` responde 502. O
   app mostra "O endereço não respondeu (HTTP 502)." de forma
   controlada (cobre "fonte fora do ar" na instalação). **Bloqueia**
   os testes de catálogo até o feed voltar (só o dono consegue).
   Captura: `testes-0.2.0/windows-feed-http502.png`.
3. **Windows: janela ficava ~6,7 s na tela depois do X** com HLS
   tocando (gravar + desligar o motor), parecendo travada.
   **Corrigido** em `a1f6de6` (esconde a janela primeiro): janela some
   em 0,1 s, posição gravada (1:50 → 1:56), processo termina logo
   depois.
4. **TCL: painel do player, qualidade manual — não conclusivo por
   automação** (resolvido na rodada final com o controle: ver seção 3).
   Registro original:
   automação.** Pelo `adb input`, o D-pad entrou em "Repetir" em vez
   de "Qualidade", nenhuma opção mostrava foco visível, e o BACK
   fechou o painel inteiro. A TCL estava muito carregada (load
   average 21) e com pop-ups do sistema. Repetir com o controle
   remoto antes de concluir. Captura:
   `testes-0.2.0/tcl-painel-repetir-sem-foco.png`.
5. **Celular (e janela baixa do Windows): painel de configurações
   saía pelo topo.** Em paisagem no celular, Idioma/Legendas ficavam
   acima da tela e Repetir cortado: fora da TV o painel não tinha
   teto. **Corrigido**: com menos de 480 de espaço acima da
   engrenagem, o painel ganha teto e rola; com espaço de sobra nada
   muda. Testes novos no celular deitado e na janela 464x231 (falham
   sem a correção). Capturas: `testes-0.2.0/celular-painel-paisagem-
   antes.jpg` e `...-depois.png`.

6. **TCL: vídeo travando e menus lentos** com o APK de `683f847`
   (debug, caminho antigo `vo=gpu` + `mediacodec-copy`): log com
   "Audio/Video desynchronisation". Duas causas somadas: (a) a saída
   direta do MediaCodec ainda não estava commitada → **commitada em
   `ff3c455`** (separada dos menus da TV); (b) APK debug numa TV com
   6 dias ligada (95 MB livres, swap 520 MB, load 24). Com o
   **release** e a TV reiniciada, rodou liso.
7. **TCL: barra do player não sumia** com o foco nela, mesmo parada
   (contrário à spec 12.2). **Corrigido** em `a9984aa`: some após
   alguns segundos sem tecla; cada tecla rearma.
8. **Retomada e troca de qualidade mostravam o início do vídeo
   (título)** antes do ponto salvo — efeito do gate de prontidão
   validado (toca até o primeiro avanço real antes do seek), em todas
   as plataformas. **Corrigido** em `a9984aa` só no visual: "Ajustando
   a posição…" cobre do open até o vídeo andar a partir do ponto
   salvo. Conferido na TCL ("funcionou perfeitamente").

## 1. Celular físico (Xiaomi 24069PC21G, Android 16)

Tela 1220x2712 a 480 dpi (~406x904 dp), navegação de 3 botões. APK
debug de `08b6633` + correção do painel (problema 5). A HyperOS
bloqueou toques por adb (`INJECT_EVENTS`); o usuário tocou e a
conferência foi por captura de tela e log (`[player-diag]`,
`[hls-resume]`, `history.json`, `startup_guard.json`).

| Caso | Resultado |
|---|---|
| Retrato e paisagem (abas) | OK (relato + captura) |
| Toque mínimo de 48 dp | OK (cantos e card; coberto também por teste) |
| Navegação inferior, voltar de Ajustes → Início, sem seta | OK |
| Catálogo | OK (19/10): fonte instalada e ativa, mux-smoke aberto pelo catálogo, histórico com o ID `owned.test:mux-smoke` e o item anterior preservado |
| Reprodução | OK: HLS 1080p, `mediacodec-copy`, `VO: [gpu]` |
| Pausa/play | OK (`pause=true/false`) |
| Seek ±10 s, toque duplo, arrastar a barra | OK (seeks no log nos alvos esperados) |
| Mudo | OK (`volume=0` / `volume=100`) |
| Tela cheia (paisagem) | OK; painel de configurações cortado → **corrigido** (problema 5) |
| Voltar | OK (posição gravada: 9:02) |
| Retomada | OK (`[hls-resume] targetMs=297950`, retomou em 4:57) |
| Tela acesa durante o vídeo | OK (`KEEP_SCREEN_ON` + wake lock; acesa por 26 s+ com apagar em 15 s) |
| Modo seguro | OK pelo relato; ao fim `manualSafeMode=false`, sem queda no arranque |
| Diagnóstico / Exportar relatório | OK pelo relato |

## 2. Windows (125%, 3440x1440, build release de `a1f6de6`)

| Caso | Resultado |
|---|---|
| Janela pequena 480x270 | OK (fileira única, sem estouro) |
| Janela grande | OK (card de desktop 880) |
| Catálogo | OK (19/10): aprovar → instalar desativado → ativar → atualizar ("Catálogo atualizado: 1 item.") → abrir → mux-smoke → reproduzir; o X volta ao catálogo |
| HLS (mux-smoke por link/histórico) | OK |
| Qualidade (720p e volta para Automática) | OK, posição preservada (1:01 → 1:15) |
| Retomada | OK (retomou em 0:35) |
| Histórico | OK ("parou em 1:38") |
| Erro controlado (link `video.invalid`) | OK: "Não foi possível reproduzir" + Tentar novamente / Editar link / Fechar |
| Fonte fora do ar (instalação) | OK: "O endereço não respondeu (HTTP 502)." |
| Fechar pelo X | OK após a correção 3 |

## 3. TCL (BeyondTV, Android 9, 1920x1080 a 320 dpi)

Rodada final (19/10): APK release de `ff3c455` + `a9984aa`, TV
reiniciada, conferência pelo usuário com o controle remoto (o build
release não grava `[player-diag]`).

| Caso | Resultado |
|---|---|
| D-pad no Início e abrir o item | OK |
| Catálogo | PENDENTE: feed 502 de novo durante a rodada |
| Fonte fora do ar | OK: a fonte passa a "Erro" na lista e o app segue usável |
| HLS | OK, liso: `VO: [mediacodec_embed]` (saída direta) |
| Qualidade automática | OK: "Automática · 288p" (teto da TV fraca) |
| Qualidade manual | OK: foco visível no painel, setas não aplicam, OK aplica 720p, posição preservada, sem o início do vídeo aparecer |
| Barra some parada | OK após a correção 7 |
| Retomada | OK, coberta até o ponto salvo (correção 8) |
| Rede fria | OK: "Não foi possível reproduzir / Não há conexão suficiente para carregar este conteúdo."; religada a rede, voltou perto de onde parou |
| Histórico | OK (saída gravou a posição) |
| BACK no player | Sai salvando para a tela anterior (spec 18). O usuário notou; mudar para "primeiro BACK esconde a barra" fica como decisão |

## 4. Comuns

Conclusão em 97%, "Ver de novo", modo seguro e diagnóstico: não
executados nesta rodada (cobertos por testes automatizados; ficam
para a rodada completa com o celular físico).

## Para fechar a rodada

- [x] Catálogo no celular e no Windows (19/10).
- [ ] Catálogo na TCL (feed temporário em 502; repetir quando voltar).
- [x] Celular físico executado (seção 1).
- [x] TCL com o controle remoto: qualidade manual, rede fria e foco
      no painel (19/10, release).
- [ ] Decidir o BACK no player da TV (manter a spec 18 ou esconder a
      barra primeiro).
- [ ] Só com tudo verde: bump para 0.2.0, checklist de release e tag.
