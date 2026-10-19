# Resultados — pacote de testes finais (0.2.0, sem tag)

Execução de `docs/TESTES_FINAIS_0.2.0.md` em 18/10/2026. **Rodada
incompleta**: falta todo o catálogo (o feed temporário caiu) e, na
TCL, qualidade manual e rede fria. Celular físico executado (seção 1). Sem tag `v0.2.0`; `v0.1.0`
intacta em `bd3270a`.

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
| Celular | APK debug de `08b6633` + correção do painel (problema 5, depois commitada em `75a02f9`) |

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
| Catálogo | BLOQUEADO (feed 502); mux-smoke aberto por link |
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
| Catálogo | BLOQUEADO (feed 502) |
| HLS (mux-smoke por link/histórico) | OK |
| Qualidade (720p e volta para Automática) | OK, posição preservada (1:01 → 1:15) |
| Retomada | OK (retomou em 0:35) |
| Histórico | OK ("parou em 1:38") |
| Erro controlado (link `video.invalid`) | OK: "Não foi possível reproduzir" + Tentar novamente / Editar link / Fechar |
| Fonte fora do ar (instalação) | OK: "O endereço não respondeu (HTTP 502)." |
| Fechar pelo X | OK após a correção 3 |

## 3. TCL (BeyondTV, Android 9, 1920x1080 a 320 dpi)

APK de `a1f6de6` instalado por cima (dados mantidos).

| Caso | Resultado |
|---|---|
| D-pad no Início e abrir o item | OK |
| Catálogo | BLOQUEADO (feed 502) |
| HLS | OK (tocando; nesta árvore a saída é a antiga, sem MediaCodec direto) |
| Qualidade automática | OK: "Automática · 288p" (teto da TV fraca) |
| Qualidade manual | NÃO CONCLUSIVO (problema 4) |
| Retomada | OK (`[hls-resume] targetMs=113500`, retomou em 1:53) |
| Rede fria | NÃO EXECUTADO: desligar a rede derruba o adb por Wi-Fi |
| Histórico | OK (saída gravou 4:56) |
| Fonte fora do ar | Coberto no Windows; na TCL depende do feed |

## 4. Comuns

Conclusão em 97%, "Ver de novo", modo seguro e diagnóstico: não
executados nesta rodada (cobertos por testes automatizados; ficam
para a rodada completa com o celular físico).

## Para fechar a rodada

- [ ] Religar o feed temporário (ou publicar o definitivo) e repetir o
      catálogo nas três plataformas.
- [x] Celular físico executado (seção 1); falta só o catálogo nele.
- [ ] TCL com o controle remoto: qualidade manual, rede fria e foco
      no painel.
- [ ] Só com tudo verde: bump para 0.2.0, checklist de release e tag.
