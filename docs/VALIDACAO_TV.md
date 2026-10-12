# Validação em aparelho de TV (Fase 4)

Checklist para rodar antes de cada versão relevante (§26.15.4), num
aparelho real. A suíte automatizada cobre a lógica (311 testes,
`test/tv_navigation_test.dart` + `test/exit_slider_test.dart`); isto cobre o que só o sofá revela.

## Aparelho (§24.8 — decidido 11/10/2026)

- [x] TCL 55" (BeyondTV), Android 9 (SDK 28), 192.168.1.8. Sem
  "depuração sem fio" (Android antigo): adb via rede após ligar
  **Depuração USB** + autorizar o diálogo na TV (`adb connect
  192.168.1.8`). Modelo registrado aqui: TCL 55" BeyondTV / Android 9.
- [ ] Android TV / Google TV (leanback). Tizen está fora: Flutter não
      tem alvo Tizen oficial (exigiria o fork da Samsung) — registrado
      como limitação.

## TV física — TCL 55" BeyondTV / Android 9 (11/10/2026)

Primeira sessão em aparelho real. GPU ARM **Mali-470 MP, OpenGL ES
2.0, sem Vulkan** (`dumpsys SurfaceFlinger`); Flutter 3.47/Impeller
exige Vulkan 1.1 ou GLES 3.0+ e o SDK atual não tem mais fallback
Skia (`--no-enable-impeller` removido). Resultado: **zero frames
renderizados (tela branca real, screencap prova)** com a árvore de
semântica 100% montada (dumps exibem onboarding completo). Não é
bug do app nem travamento: é incompatibilidade engine↔GPU.

Consequência metodológica: nesta TV vale tudo que dump/logcat
provam (boot sem crash, foco, ordem de travessia, D-pad, relógio
de reprodução, persistência, diálogos, permissões). Prova de
**pixels** (frames de vídeo, anel de foco, overscan visual) exige
TV com Vulkan ou GLES 3.0+ (qualquer TV 2021+ típica) — §24.8.

Correção aplicada nesta sessão: `main` injeta `NoOpWindowService`
fora do desktop (antes, `windowManager.ensureInitialized` lançava
`MissingPluginException` não-fatal em todo boot Android, sujando
o diagnóstico do guarda de arranque).

### Resultados — TCL BeyondTV (dumps + logcat)

- Boot sem crash; onboarding com "Começar" focado; D-pad só
  (ui_boot). Começar → inicial; UP ancora na Biblioteca (ui_nav).
- Biblioteca lista cards semeados ("sample 0:05", "tv long 1:30");
  DOWN + OK abre o player (ui_bib2).
- Decode real: sample 5 s tocou até "Reprodução concluída" 2×;
  overlay nasce com "Reproduzir novamente" focado (F2-concluído).
- BACK salva e volta: 0:39 (history 39466 ms) e 1:10; card mostra
  "parou em"; foco restaurado no card de origem.
- Retomada exata 2x: reabrir continuou de 0:39 e 0:43 (dump com
  tempo + % + "Reproduzir" pausado). Anomalia 1:10->0:03 RESOLVIDA
  (ver TV-RESUME): 1:08 semeado caiu em 1:17 e 1:18 (2 cold-starts).
- Pausa congela (tempo + % + botão Reproduzir); relógio tabular.
- Metodologia: vídeo TOCANDO quebra o idle do uiautomator de
  forma INTERMITENTE (falha ≠ tocando, sucesso ≠ pausado);
  JSON (history/library) é o árbitro de posição, não o dump.
  `input text` troca `/` por `-` nesta TV (não usar p/ caminho).
  IME Gboard TV existe e come setas com campo focado (BACK
  dispensa; a nota "TV real sem IME" do AVD estava errada).
- TV-RESUME RESOLVIDO (11/10/2026, 2a sessao fisica). Raiz dupla:
  (1) seek antes de o mpv frio conhecer o arquivo era descartado -> _waitForDuration (so busca apos a duration chegar, lida no motor, nao no espelho do widget);
  (2) as 5 re-tentativas queimavam nos primeiros ~5 s, antes de a janela fria fechar -> ESPACADAS (1/4 s, max 5 em ~20 s, deadline 25 s), timer periodico cancelavel (dispose/nova abertura).
  Prova: 1:08 semeado -> relogio 1:17 (ui_s3) e 1:18 (ui_t2) em 2 cold-starts c/ force-stop (antes: 1:10->0:03, 1:14->0:11). Suite 307/307 + analyze limpo (fixtures de retomada ganharam duration).

### 2a sessao fisica (11/10/2026, mesmo aparelho)

- Painel por D-pad (ui_p1-ui_p6): abre na engrenagem; DOWN ancora o foco
  na 1a fileira (Idioma); setas percorrem em ordem visual (Idioma,
  Legendas, Girar, chips de velocidade); BACK fecha o painel e devolve o
  foco a engrenagem (spec 18). Menor: painel abre sem autofocus (foco na
  raiz; 1a seta ancora) - avaliar autofocus na 1a fileira.
- Ancoragem do painel PROVADA por geometria (spec 3.5): painel x896-1576
  (centro 1236) = centro-x da engrenagem (x1172-1300); base do painel y908,
  20 px acima do topo da engrenagem (y928).
- Velocidade 1,5x PROVADA funcionalmente (ui_p7/ui_p8 + JSON): fim
  acelerado em ~11 s de parede (overlay concluido) + replay do 0:00 com
  relogio avancando ~1,5x (history 46,9 s apos ~31 s de parede; 1:07 apos
  resume de 0:46). Chip selecionado nao expoe estado em semantica
  (Button sem selected) - confirmacao visual fica p/ TV com pixels.
- Girar horario ativa sem crash (ui_g2/ui_g3); rotacao e visual-only
  (info mostra so titulo/duracao/fonte) - pixels em TV nova. BACK fecha
  dialogo+panel de uma vez e fica no player (hierarquia OK).
- Legendas sem faixas (ui_l3/ui_l4): submenu "Nenhuma legenda disponivel",
  sem crash; BACK volta ao player com foco na engrenagem.
- Tela cheia por D-pad (ui_l1/ui_l2): entra pela fileira; BACK sai do
  modo antes de fechar, com foco em "Tela cheia" (spec 18).
- Modo seguro PROVADO (ui_m1-ui_m5): pendingBoots=2 semeado -> faixa
  "Modo seguro: add-ons nao carregados (2 falhas no arranque)" + botao
  Diagnostico alcancavel por D-pad; boot seguinte limpo zerou o contador
  (pendingBoots 0) e removeu a faixa; sem crash. Nao-carregamento de
  add-on instalado nao exercitado (nenhum instalado; path coberto por
  teste unitario + revisao).
- Higiene de zona (main.dart): binding era criado na zona raiz e runApp
  na zona guardada -> "Zone mismatch" registrado TODO boot. Extraido
  _boot() executado DENTRO da zona; recordError agora leva pilha (4
  linhas truncadas, sem PII) e erro de zona vai ao logcat (debugPrint).
  3 boots limpos seguidos sem novo registro; 1 registro residual no 1o
  boot apos reinstall (16:51, possivel transiente de dexopt) - reabrir
  se repetir (agora com pilha).
- Correcao de diagnostico: logcat mostra "Impeller opt-out deprecated"
  (shell.cc) - o app roda SEM Impeller nesta TV; a tela branca e
  Skia-vs-Mali-470 (ou superficie), nao Impeller-vs-GPU. Origem do
  opt-out nao localizada (manifest/gradle/config global limpos; provavel
  fallback automatico ou default do build) - sem impacto: nenhum backend
  apresenta frames nesta GPU. Nao mexer (trocar backend perturbaria o AVD).
- Anomalia nao-reproduzida (ui_z2-z4): apos um force-stop+start na janela
  do reinstall, dumps mostraram player (AppBar, overlay concluido) em vez
  da home, e um BACK salvou 0:15 com timestamp fresco. Reboot limpo com
  PID verificado (1596) abre a home; 5+ boots sem repetir; codigo nao tem
  restauracao de rota. Atribuido a flake da bridge/stale-tree + corrida na
  janela do reinstall; integridade do history mantida (card mostra 0:15).
- Licoes re-confirmadas no aparelho: dumps do player congelam apos
  playback (bytes identicos; JSON e o arbitro); video tocando quebra o
  idle do uiautomator (pausar antes de dumpar); null-root intermitente
  (re-tentar apos segundos).

## Instalação e boot (Task 15)

- [ ] APK instala pela Play Store ou `adb install`.
- [ ] O app aparece na fileira de apps do launcher da TV (categoria
      leanback; banner provisório = ícone — TODO banner 320x180).
- [ ] Abre direto em paisagem, sem onboarding bloqueante e sem pedir
      toque (D-pad basta desde a primeira tela).
- [ ] Sem crash no boot com/sem rede.

## Só D-pad + OK + voltar (Tasks 12–13)

- [ ] Setas movem o foco em todas as telas; Enter ativa; nada exige
      outro botão.
- [ ] Foco sempre visível, com contraste sobre o fundo (§18, §26.6).
- [ ] Ordem do foco segue a ordem visual (cima→baixo, esq→dir).
- [ ] Player, barra visível: setas navegam; esquerda/direita no
      slider ajustam; Enter no slider sai para os botões (§12.2).
- [ ] Player, barra oculta: setas buscam/volume e reexibem; Enter
      reexibe sem efeito colateral.
- [ ] Subir da fileira de botões ancora na AppBar; descer da AppBar
      cai no slider; volume sai para o mudo.
- [ ] Voltar fecha painel antes de sair; em tela cheia/cinema, voltar
      sai do modo antes de fechar o player (§18, §12.2).
- [ ] Diálogos prendem o foco; Cancelar nasce focado (OK imediato
      nunca destrói — §26.6).
- [ ] Pop-up de repositórios: setas navegam, Enter escolhe, voltar
      fecha sem aplicar.

## Modo TV (Task 14)

- [ ] Configurações → Modo TV: botões ≥ 64 px, texto maior, margens
      maiores (sem corte por overscan nas bordas).
- [ ] Com foco na barra, ela não some sozinha; ao sair dela, some em
      ~4 s (§12.2).
- [ ] Layout 16:9 sem estouro nem coluna espremida (1920x1080 e
      3840x2160).

## Reprodução no aparelho (§26.10, real)

- [ ] Vídeo curto e longo (rede estável): início, pausa, busca,
      retomada, troca de mídia.
- [ ] Rede instável: buffer indica, UI responde, timeout vira erro
      legível por tipo (fonte/rede/decodificador).
- [ ] Erro de add-on/fonte diz de quem é a culpa, sem derrubar o app.
- [ ] Idioma preferido ausente avisa ("sem faixa em …"); info mostra
      a fonte (arquivo local / add-on); títulos intactos (§26.12).
- [ ] Diagnóstico exportável sem dados sensíveis (§26.10).

## Regressão rápida (fumaça, ~5 min)

1. Boot → biblioteca → play → pausa → busca → voltar (salva).
2. Configurações → Modo TV → player → voltar (persiste).
3. Add-ons → detalhes → Remove → Cancelar via OK (mantém).
4. Diagnóstico → exportar → conferir sem CPF/caminho/URL.

## Resultados — AVD PlayerTV (tv_1080p, API 36, 2026-10-10/11)

Pilotagem só D-pad + OK + voltar via `adb shell input keyevent`
+ `uiautomator dump` (71 dumps em `.fl-tmp/ui*.xml`). APK debug com
leanback instalado; `sample.mp4` (5 s) e `tv_long.mp4` (3 min,
gerado por ffmpeg) exercitados.

### Passou no aparelho

- Boot leanback em paisagem, sem crash; onboarding com "Começar"
  focado; boot seguinte cai direto na inicial com card focado.
- Decode real: `sample.mp4` tocou até "Reprodução concluída";
  `tv_long.mp4` avançou o relógio (cartão salvou "parou em 0:32"
  e depois "parou em 2:14").
- BACK hierárquico: erro/concluído/reproduzindo → salva sessão
  ("Continuar assistindo") e restaura o foco de origem.
- Modo TV liga por D-pad (switch `checked=true`); alvo Pausar
  com 128x128 px; margens laterais 115 px (overscan OK).
- Abertura do player foca Pausar; setas navegam Pausar↔Retroceder
  e a fileira da AppBar; card da biblioteca tem autofocus.
- Menu Opções navega em ordem visual; configurações navegam por
  D-pad (switches alternam com OK).
- Nenhum crash em ~70 telas; posição salva/restaurada no cartão.

### Achados (Fase 4b — corrigir e revalidar no aparelho)

- **F1 D-pad morto com controles ocultos (crítico).** Setas e OK
  não buscam, não mudam volume, não reexibem, não pausam. Causa
  parcial confirmada em código: o binding usa
  `SingleActivator(enter)`, mas DPAD_CENTER chega como
  `LogicalKeyboardKey.select` no Android
  (`player_screen.dart:332`). Setas ocultas também não
  dispararam — investigar rota do evento no aparelho (os testes
  widget injetam teclas por caminho que não reproduz o
  roteamento do Android; teste verde ≠ aparelho).
- **F2 Overlays de erro/concluído prendem o foco (crítico).**
  Foco cai no texto estático tela-cheia; setas e TAB não
  alcançam os botões (Tentar novamente/Remover/Fechar,
  Reproduzir novamente) — focáveis mas fora da travessia. Só
  BACK escapa. Corrigir: texto fora do foco + autofocus no
  primário.
- **F3 Remover sem confirmação (crítico).** OK em Remover no
  menu do card apaga na hora, sem diálogo — viola "OK imediato
  nunca destrói". Confirmado em código: `history.remove` /
  `library.remove` diretos em home/library/favorites/history;
  só add-on confirma. Adicionar diálogo (Cancelar focado).
- **F4 TextField prende UP/DOWN.** No campo de caminho, setas
  verticais não saem do campo (só TAB escapa; remoto não tem
  TAB). Dar saída por D-pad.
- **F5 DOWN da AppBar = volume, sem entrar nos controles.**
  Com barra visível e foco na AppBar, UP/DOWN ajustam volume
  (100→90→80 observados) em vez de navegar; a fileira de
  controles só é alcançável na abertura (foco nasce em Pausar).
- **F6 LEFT além de Retroceder perde o foco.** Foco cai na raiz
  e setas não recuperam (só TAB; BACK escapa salvando).
  Investigar `_PlayerTraversalPolicy` + foco dos sliders no
  aparelho.
- **F7 Opções inalcançável por direcional.** Botão dentro dos
  bounds do card: RIGHT do card pula para a barra superior;
  TAB alcança. Ajustar travessia direcional.
- **F8 Sem permissão de mídia (Android).** Manifest não declara
  `READ_MEDIA_VIDEO`/`READ_EXTERNAL_STORAGE`; arquivo em
  `/sdcard/Movies` falha ao abrir. Declarar + pedir em runtime.
- **F9 Diagnóstico errado para arquivo local.** Falha de
  abertura local mostra "Não há conexão suficiente": o mpv
  relata "Failed to open ... Permission denied" e o
  classificador mapeia "failed to open" → rede
  (`playback_state.dart:54`). Fonte local nunca deveria dizer
  rede; adicionar "permission denied" → fonte.
- **F10 Foco frio.** Inicial/biblioteca/abrir-video/config vêm
  sem foco (1ª seta só ancora). Autofocus na ação primária.

### Limites do ambiente (não-bugs; pedem aparelho real)

- Saída de vídeo (vo/mpv) quebrada no emulador headless em
  todos os modos GPU (frames idênticos/pretos,
  `eglCreateContext EGL_BAD_ATTRIBUTE`); relógio anda pelo
  áudio. Renderização real, retomada com seek (travou aqui) e
  visibilidade do anel de foco precisam de TV física (§24.8).
- Screenshots inúteis aqui (tela preta); validação foi por
  hierarquia + rótulos/posições salvas.
- Emulador foi deixado rodando (`PlayerTV`); dados do app
  foram limpos no último ciclo (`pm clear` + reinstalação dos
  mp4 em `/data/user/0/com.example.player/files/`).

## Revalidação — F1/F8/F9 ✅ (2026-10-11, APK rebuildado)

Suíte 254/254 + analyze limpo. Correções em
`player_screen.dart` (`_handleHiddenKeys` global + `select`),
`playback_state.dart` (permissão → fonte) e manifest
(`READ_MEDIA_VIDEO`).

- **F1 ✅.** Handler global dispara no aparelho (log confirmou
  guardas + `_poke`): DOWN oculto 90→80% + reexibe + restaura
  foco; OK (`select`) oculto reexibe sem seek; 3× RIGHT oculto
  → cartão "parou em 1:17" (77 s >> ~40 s corridos: +30 s de
  seek). Disparo único (passos exatos de 10).
- **F8 (manifest) ✅.** `dumpsys` confirma `READ_MEDIA_VIDEO`
  declarada; com `pm grant`, `/sdcard/Movies/sample.mp4` tocou
  até "Reprodução concluída". Pedido em runtime segue pendente.
- **F9 ✅.** Sem grant, o mesmo arquivo agora diz "Este arquivo
  não está mais disponível no caminho salvo" (fonte), nunca
  rede.

### Revisão de escopo (lição metodológica)

- **Dumps do uiautomator atrasam 1–4 s+** neste emulador: o log
  provou controles visíveis 35.479→39.472 enquanto o dump
  mostrava oculto. Janela de 4 s do auto-hide vira cara-ou-
  coroa no dump. Regra: o observável temporal (janela) se prova
  por log; dump só vale para estado latched (foco, telas,
  textos, posições salvas, switches).
- Releitura com essa lente: o "D-pad morto" original era
  parcialmente artefato — as setas ocultas provavelmente sempre
  funcionaram (ui36 capturou uma); o bug real era o OK
  (`enter` sem `select`, certeza estática). O handler global
  permanece como correção certa (cobre `select`, independe de
  foco) e está provado no aparelho.
- Achado lateral p/ F2: concluído "com a seguir" foca o botão
  primário, mas DOWN cai no texto do overlay e não sai mais
  (UP/DOWN presos) — o texto precisa sair da travessia.

### Revalidacao F2/F3 pos-fix (build atual, 263/263 testes) -- 2026-10-11

- **F2-erro PROVADO no aparelho (mecanismo explicito novo).** Overlay de erro abre com
  "Tentar novamente" FOCADO (ui_bp1); circuito 2x2 completo por D-pad: DOWN Tentar->Remover,
  RIGHT->Fechar (ui_be4), UP->Localizar (ui_be5), LEFT->Tentar (ui_be6); OK no Tentar refaz
  e o foco VOLTA ao Tentar (ui_be7, latch _wasOverlayUp reseta pelo loading). Layout em Wrap
  2 colunas: DOWN de Tentar cai em Remover (fileira de baixo), nao e travamento.
- **F2-concluido BLOQUEADO no aparelho (ambiente, nao codigo).** Relogio mpv congelado em
  0:00 (duas leituras com 10 s de intervalo, ui_p1/ui_p2) apesar de status=playing: vo EGL
  (EGL_BAD_ATTRIBUTE) + ao OpenSL ("Configuration error") quebrados no AVD headless. Seek
  alem do EOF nao dispara completed; mp3 de 6 s falha ao abrir (sem relogio). Sessao anterior
  viu sample.mp4 chegar ao fim -- regressao do ambiente. Widget-test prova o concluido (38/38 TV,
  inclui "concluido apos hide" + travessia) com o MESMO no/hook do erro (provado acima).
  Revalidacao do concluido no aparelho exige TV fisica (24.8) ou AVD com GPU funcional.
- **F3 PROVADO no aparelho (player).** OK em Remover abre "Remover da biblioteca?" com
  "Cancelar" FOCADO (ui_f3a, 26.6); OK cancela e devolve o foco ao Remover (ui_f3b);
  RIGHT->Remover + OK remove, cascata biblioteca+historico (sem beep no home, ui_f3d) e fecha.
- Achado p/ F5: apos poke, o foco restaura em "Voltar" (AppBar), nao num controle (ui_p1/ui_p2);
  e plausivelmente a causa-raiz do F5 (DOWN da AppBar = volume em vez de entrar nos controles).


### F2-concluido DESBLOQUEADO (reboot do AVD restaurou o relogio mpv)

- Apos `adb reboot`: sample.mp4 de 5 s terminou sozinho em ~6 s; overlay "Reproducao concluida
  / A seguir: tv long" abriu com "Reproduzir novamente" FOCADO (ui_r1/ui_r2) -- o caso exato
  regredido (fim natural com barra oculta). RIGHT->Favoritos (ui_c2), RIGHTx2->Proximo (ui_c5),
  OK no Proximo tocou tv long (ui_c6, ativacao OK no overlay funciona). F2 100% provado.
- Licao: clock congelado era estado degradado do AVD, nao falha do app; reboot resolve.


### Checkpoint F4-F8/F10 no aparelho (build final, 281/281 testes) -- 2026-10-11

- **F4 PROVADO.** Abrir video nasce com "Procurar arquivo" focado (ui_qo2); DOWN entra no
  campo; UP sai do campo para o Procurar e ENTER abre o picker do sistema (f4up2.png).
  DOWN-simétrico cobre o mesmo código (testado 7/7 em widget). Quirk: Gboard do AVD come
  setas com teclado aberto (digitou "q"!); TV real sem IME não tem isso. Dispensar com BACK.
- **F5 PROVADO via logcat** (dumps do player congelavam; pixels+log como árbitros). F5a:
  hide com foco na fileira -> stash non-null -> restore volta p/ fileira (hasFocus=true
  no hide seguinte, duas vezes). F5b: UP p/ AppBar -> hide hasFocus=false -> restore
  stashNull=true -> fallback nextFocus (Voltar). Foco nunca mais ancora na AppBar após poke.
- **F6 PROVADO visualmente.** Anel azul de 3px ao redor do slider focado (ring1.png,
  trav1.png). Slider continua invisível nos dumps (ponto cego da ferramenta).
- **F7 PROVADO.** RIGHT do corpo do card -> "Opções" focado (ui_qf7); LEFT volta.
- **F10 PROVADO.** Configurações abre com switch Tema focado (ui_qs1); home vazio abre
  com "Abrir arquivo" focado (ui_qv2 + screenshot). Listas cheias já tinham index==0.
- **F8-runtime PROVADO (allow + deny).** Instalação virgem: abrir local mostra diálogo do
  sistema (ui_p8a/ui_qv3). Allow -> toca (ui_p8b: tv_long 0:42). Don't allow -> overlay F9
  "não está mais disponível no caminho salvo" com Tentar focado (ui_qv7: F8+F9+F2 juntos).
- **F2-concluído RE-PROVADO no build final** (ui_qz1): sample termina sozinho ->
  "Reprodução concluída" com "Reproduzir novamente" focado. F1/F3: código intacto desde
  as provas; sem regressão (suíte verde).
- Metodologia: vídeo TOCANDO quebra o idle do uiautomator (pausar antes de dumpar); dumps
  do player congelam após playback (bytes idênticos!); DPAD_CENTER chega como Select
  (confirmado no log, cobre F1); Gboard intercepta setas/enter com campo focado.

### Banner + Leanback + validacao minima (build atual, 287/287 testes) -- 2026-10-11

- **Banner 320x180 PROVADO no launcher.** `drawable-xhdpi/tv_banner.png`
  empacotado (aapt: `banner='res/drawable-xhdpi-v4/tv_banner.png'` +
  `leanback-launchable-activity`); tile "Player" visivel na fileira
  "Installed Apps" do Google TV (v_apps3.png).
- **Auto-deteccao Leanback PROVADA.** Instalacao virgem no AVD-TV
  (`android.software.leanback` + `hardware.type.television`): prefs
  gravadas com `"tvMode":true,"tvModeAuto":true` sem toque humano.
  Interruptor manual desliga o auto; "Detectar TV automaticamente"
  reaplica a deteccao.
- **Render OK.** Home em modo TV (v_home2.png); player com controles
  grandes (v_play.png, 0:04/3:00). Frames de video pretos no AVD
  headless (EGL_BAD_ATTRIBUTE no logcat, decode/relogio OK) -- prova
  de frame exige TV fisica (24.8).
- **Foco OK.** "Abrir arquivo" nasce focado (F10 de pe); ordem visual
  nos dois sentidos (Retroceder <-> Reproduzir <-> Avancar, dumps
  v_l/v_r2); UP fileira -> AppBar; DOWN AppBar -> slider com ANEL AZUL
  visivel (v_cinema.png, F6 re-provado); ENTER sai do slider.
- **Setas OK.** Direcional em home e controles; slider consome setas
  (by design, _ExitSlider documenta).
- **Seek oculto EXATO.** Pausado: RIGHT 0:12 -> 0:22 (v_c4),
  LEFT 0:22 -> 0:12 (v_c6). Passos exatos de 10 s, sem disparo duplo.
- **Voltar OK.** BACK sai do player para a home, que mostra "parou em
  0:12" com barra de progresso; history.json + library.json com
  positionMs/lastPositionMs = 12172 (v_back.png).
- **Controles OK.** Show/hide 4 s, persistencia-TV com foco na barra,
  pausa/retomada por OK e tap; replay pos-fim funcionou de passagem
  (CENTER no "Reproduzir novamente" apos fim natural).
- Licao metodologica: gaps longos com video TOCANDO invalidam a linha
  de base (o video terminou e o overlay F2 capturou meu CENTER ->
  replay; posicao "0:36 -> 0:12" explicada, sem bug). Pausar antes de
  analisar; setas com barra oculta viram seek/volume (meus DOWNs "que
  nao funcionavam" eram volume-down + poke apos auto-hide).

### F11 (slider trap) + TV-RESUME + error-exit -- TCL 55" BeyondTV fisica (311/311) -- 11/10/2026

- **F11 PROVADO na TV fisica.** Settings Volume slider: DOWNx3 chegou no slider
  (ui_o2, 100%); UP nao saiu (armadilha confirmada: setas viram ajuste, 100->95).
  Root cause: `Slider` consome OK antes de Shortcuts/onKeyEvent/HardwareKeyboard
  (provado em widget-test com 3 tentativas falhas). Fix: widget compartilhado
  `ExitSlider` (override de `Actions({ActivateIntent})`) aplicado a progress+volume
  do player e volume das settings; `exit_slider_test.dart` 3/3. Na TV com o fix:
  OK no slider moveu o foco para a fileira (focused=false, ui_o9); Restaurar
  switch intermedio nao responde (quirk de foco do switch, nao do slider):
  DOWN do slider pula Restaurar e ancora em "Janela sempre no topo" (ui_o10);
  Dx4 a partir dai atravessa os switches e chega em Diagnostico (ui_o15) e
  Exportar abre o seletor do sistema (ui_o18, "Salvar como", F11 100% ponta-a-ponta).
- **TV-RESUME PROVADO 2x cold-start.** Semeado 1:08 (68000ms): clock 1:17 (ui_s3)
  e 1:18 (ui_t2). Fix: `_waitForDuration` le o motor (nao o espelho do widget)
  + retries espacados 1/4s max 5 em deadline ~20s/25s, Timer cancelavel.
- **Error-exit preservation PROVADO.** Semeado 1:08 + arquivo ocultado: overlay
  de erro + BACK preservou 68000ms em history+library (antes zerava).
- **Checklist TV:** painel D-pad abre ancorado (x896-1576 centrado na engrenagem
  x1172-1300, base y908 20px acima da gear y928); velocidade 1.5x funcional
  (~11s wall + historico 46.9s/31s); Girar sem crash; Legendas empty state;
  fullscreen BACK-first; safe-mode banner + clean reboot.
- **Zona residual:** 1 entrada 16:51 persiste no guard JSON com contador 0;
  `_boot()` zonado + recordError com stack (main.dart/startup_guard.dart);
  3 boots limpos desde entao. Side-effect restaurado: initialVolume 80%->100%.
- Pixel items (frame de video, anel, overscan) seguem diferidos p/ TV Vulkan/GLES3.

### Leanback launcher -- TCL 55" BeyondTV fisica -- 11/10/2026

- **APK OK (aapt).** `banner='res/drawable-xhdpi-v4/tv_banner.png'`,
  `leanback-launchable-activity: MainActivity`,
  `uses-feature-not-required: android.software.leanback`.
- **Tile PROVADO no launcher Google TV.** Aba Apps -> "Apps instalados": tile
  "Player" com banner azul visivel (lb_row2.png, ultima fileira); foco D-pad
  chega ao tile (lb_player.png, tile ampliado + rotulo "player").
- **Lancamento pelo tile PROVADO.** force-stop (PID morto) + OK no tile ->
  PID 3484 fresco, `mResumedActivity: com.example.player/.MainActivity`,
  home 100% montada (25 nos: nav rail, "Continuar assistindo", "tv long
  1:30 - parou em 1:08 - Arquivo", "Abrir arquivo", "Abrir link", ui_lb11),
  sem crash no dumpsys. Resume 1:08 intacto apos o ciclo.
- **Zona: 4o boot limpo.** Guard segue com `pendingBoots: 0` e apenas a
  entrada residual 16:51 (stale, pre-fix); nenhum erro novo no boot via
  launcher. Navegacao launcher: UP fileira -> carrossel -> menu topo;
  RIGHTx3 Início->Apps; DOWNx2 -> fileira instalados (null-root do
  uiautomator 3x, retry resolve; cards sem texto/desc exigem screenshot).
- Resta: teste manual do link autorizado (abaixo: FEITO).

### Link autorizado -- TCL 55" BeyondTV fisica (312/312) -- 11/10/2026

- **REPRODUCAO DE LINK PROVADA.** Home -> "Abrir link" (tap 580,984) -> campo
  URL -> digitacao em chunks via `input text` (string longa trunca: 77 chars
  no 1o teste, "ForBiggazes" no 2o; 5 chunks de ~17 chars funcionam) -> "Carregar
  link": `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8` (HLS) TOCOU:
  uiautomator "could not get idle state" (assinatura de video tocando) +
  BACK salvou `history.json` com `positionMs: 4983` (~5 s) no item
  `x36xhzz`/`sourceType: url` (library.json confirma a URL).
- **Achado 1 (bug real, corrigido): manifest sem INTERNET.** Todo link falhava
  com `network.offline` mesmo com internet (ping 10ms, DNS OK). Fix:
  `<uses-permission android.permission.INTERNET>` + teste de guarda
  `test/android_manifest_test.dart` (INTERNET + midia + leanback).
- **Achado 2 (fonte, nao app): GCS sample 403.** `commondatastorage.../ForBiggerBlazes.mp4`
  retorna **403 Forbidden ate com UA de browser** (curl do PC prova; bucket
  depreciado/restrito). Verbose do mpv mostrou `https: HTTP error 403 Forbidden`.
  Troca de URL de teste para mux (200 com UA ffmpeg). Diagnostico exigiu taps
  debug-only no servico (`stream.log` + `stream.error` -> `[player-diag]`,
  `logLevel: v` em debug, tudo `assert`/kDebugMode = zero impacto em release).
- **Achado 3 (fix): 403 classificava como rede.** `classifyPlaybackError` mapeava
  "http error" -> network ("sem conexao", enganoso p/ 403). Fix: '403'/'forbidden'
  -> source (mesma familia do 404) + caso na tabela `playback_recovery_test`.
- Digitacao: `input text` longo e instavel no Gboard da TV; limpar com loop de
  90x DEL funcionou; CENTER nao ativa card da Biblioteca (tap sim).
- Validacao TV fisica 100% concluida: F11, TV-RESUME, error-exit, leanback,
  link autorizado. Itens de pixel seguem diferidos p/ TV Vulkan/GLES3.

### Card Showtime + cantos -- TCL 55" BeyondTV fisica (399/399) -- 12/10/2026

- **INSTALACAO/LANCAMENTO OK.** `install -r app-debug.apk` (Success), abertura
  via `monkey ... LEANBACK_LAUNCHER` (PID 1528). `aapt dump badging`:
  `banner='.../tv_banner.png'`, `leanback-launchable-activity` MainActivity,
  `uses-feature-not-required: android.software.leanback`. Banner
  `drawable-xhdpi/tv_banner.png` com 320x180 exatos.
- **HOME OK.** Tema escuro, "Continuar assistindo" com posicoes ("parou em"),
  barras de progresso, miniatura local, placeholder e botoes. Primeira
  captura saiu branca (transiente de splash na hora do screencap; app em
  primeiro plano, sem erros Flutter) -- recaptura perfeita. Nao e bug.
- **CARD FLUTUANTE OK.** Tempo/titulo/duracao, slider total, volume+
  transporte+engrenagem, cantos (tela cheia esq; cinema/compacto/favorito/X
  dir), layout 16:9. Retomada 1:08/1:30 no D-pad (CENTER).
- **D-PAD OK.** RIGHT move o foco com destaque visivel; BACK salva (1:08) e
  volta a inicial; seek +10 exato com controles ocultos (0:07->0:16 apos
  replay); fim de video com overlay (rever/favoritar/proximo/fechar);
  botoes do overlay ativam pelo CENTER (favoritou de verdade).
- **Cantos sobre overlay OK.** Botoes visiveis acima do overlay de fim
  (regra da AppBar antiga preservada).
- **Observacao (pre-existente, sem fix):** apos o BACK, o foco caiu no card
  x36xhzz em vez do card de origem (tv long, que borbulhou p/ o topo).
  Causa: `autofocus: index == 0` sem restauracao a origem. Nao e regressao
  do card; corrigir exige logica nova (decisao do usuario).
- ClassNotFound no logcat (`OnBackAnimationCallback`, `OnBackInvokedCallback`,
  `ContrastChangeListener`, `SidecarCallback`) sao guards benignos de API nova
  no Android 9 (INFO, sem impacto).

### Escala 10-foot -- TCL 55" (408/408) -- 12/10/2026

- **CAUSA.** TV 1920x1080 a 320 dpi = viewport logico de 960x540 (celular
  esticado em 55"); o modo TV so aumentava o texto (1.15-1.3x). Icones,
  botoes, cards e linhas seguiam em escala de celular.
- **FIX.** `AppScale` (classe de exibicao: compacto/padrao/expandido/10-foot;
  modo TV sempre 10-foot) + `PlayerTheme.dark(tvMode:)` com icones 40,
  appbar 88, sliders mais grossos e linhas mais altas; cards (mini 160x90,
  paddings/gaps 2x), card do player (paddings, volume 128, tempo 96),
  alvos de toque 72 e icones semanticos escalados; texto 1.35-1.55x.
  Desktop/celular: fator 1.0, sem mudanca.
- **PROVA.** Inicial, biblioteca, player e configuracoes recapturados na TV
  fisica: linhas altas, icones e textos legiveis a distancia. 9 testes
  novos (`test/display_scale_test.dart`); 399 anteriores verdes.
- **V2.** Primeira passada (icones 32, texto 1.15-1.3x) ficou timida na
  sala; fatores elevados apos prova visual (usuario: "maior que antes,
  nada adaptativo"). Capturas brancas transitorias no relance voltaram
  ao normal com uma tecla (frame inicial, sem excecao no logcat).

### Spec 27: interface adaptativa -- TCL 55" (416/416) -- 12/10/2026

- **DIAGNOSTICO (27.1/27.10.1).** `wm size` = 1920x1080 fisico a 320 dpi
  => 960x540 logico, proporcao 1.78 (classe normal). Ampliar o desktop
  estourou a composicao: a TV ganhou composicao propria (27.2), nao
  escala unica.
- **DETECCAO (27.3/27.10.2).** `list features` informa
  `android.software.leanback` + `leanback_only`; prefs persistidas com
  `tvMode:true` + `tvModeAuto:true` (auto aplicou sozinho). Manual
  continua disponivel para aparelho sem Leanback.
- **FIX (27.4-27.7/27.10.3-6).** `TvLayout` (largura <800/800-1279/>=1280,
  ultrawide so desktop, margem segura 5% entre 16 e 48) +
  `TvLayoutTokens` por classe (icone primario/secundario, titulo/corpo/
  legenda, altura, anel, raio, miniatura, trilho, faixa de texto) +
  `TvPlayerControls` (72% ate 760, centralizada; acoes principais;
  chips Audio/Legendas/Qualidade em 2 linhas que abrem os subpaineis).
  Cantos e barra dentro da safe area; sem posicao fixa critica.
- **FOCO (27.8/27.10.7-8).** Mesmos escopos/tooltips: D-pad desce do
  play ao chip, OK abre o subpainel ancorado, voltar fecha so o painel
  (provado em captura com video rodando). Anel no token (3/3/4).
- **PROVA (27.9/27.10.9-10).** 1080p nativo: inicio, biblioteca, player,
  subpainel, voltar e configuracoes. 720p simulado (`wm size 1280x720`,
  compacto): biblioteca, erro e player (mudo sem trilho, chips em uma
  linha). 4K simulado (`wm size 3840x2160`, grande): conclusao,
  biblioteca e player (barra no teto de 760). `wm size reset` apos.
  Video mantem proporcao; Windows pixel a pixel (17 testes travam o
  desktop + 399 anteriores verdes).
- **NOTAS.** Link de teste instavel durante a sessao (falhou e voltou;
  culpa da fonte, overlay correto). Chips em linha igual com ellipsis
  de seguranca: titulo sempre visivel, valor cheio a um OK. Capturas
  brancas transitorias no relance persistem (uma tecla resolve).
