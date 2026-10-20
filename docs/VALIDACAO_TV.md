# Validação em aparelho de TV (Fase 4)

Checklist para rodar antes de cada versão relevante (§26.15.4), num
aparelho real. A suíte automatizada cobre a lógica (311 testes,
`test/tv_navigation_test.dart` + `test/exit_slider_test.dart`); isto cobre o que só o sofá revela.

## Aparelho (§24.8 — decidido 11/10/2026)

- [x] TCL 50" (v8-r851t02-lf1v660), Android 9 (SDK 28), 192.168.1.8. Sem
  "depuração sem fio" (Android antigo): adb via rede após ligar
  **Depuração USB** + autorizar o diálogo na TV (`adb connect
  192.168.1.8`). Modelo registrado aqui: TCL 50" v8-r851t02-lf1v660 / Android 9.
- [ ] Android TV / Google TV (leanback). Tizen está fora: Flutter não
      tem alvo Tizen oficial (exigiria o fork da Samsung) — registrado
      como limitação.

## TV física — TCL 50" v8-r851t02-lf1v660 / Android 9 (11/10/2026)

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

### Resultados — TCL v8-r851t02-lf1v660 (dumps + logcat)

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

### F11 (slider trap) + TV-RESUME + error-exit -- TCL 50" v8-r851t02-lf1v660 fisica (311/311) -- 11/10/2026

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

### Leanback launcher -- TCL 50" v8-r851t02-lf1v660 fisica -- 11/10/2026

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

### Link autorizado -- TCL 50" v8-r851t02-lf1v660 fisica (312/312) -- 11/10/2026

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

### Card Showtime + cantos -- TCL 50" v8-r851t02-lf1v660 fisica (399/399) -- 12/10/2026

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

### Escala 10-foot -- TCL 50" (408/408) -- 12/10/2026

- **CAUSA.** TV 1920x1080 a 320 dpi = viewport logico de 960x540 (celular
  esticado em 50"); o modo TV so aumentava o texto (1.15-1.3x). Icones,
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

### Spec 27: interface adaptativa -- TCL 50" (416/416) -- 12/10/2026

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

### Soak: reproducao continua + memoria -- TCL 50" -- 12/10/2026

- **LINK (13 min).** `x36xhzz` (10:34) tocou de 0:00 ate 2:17 em 13 min
  de relogio: a fonte entrega devagar (buffering), e o app segurou sem
  travar. Memoria (TOTAL PSS): 278 MB -> 309 -> 310 -> 313 MB;
  estabilizou apos o enchimento do buffer. Mesmo PID o tempo todo.
- **LOOP (5 min).** `tv long` local com Repetir item (~3 voltas):
  241 MB -> 233 MB, tocando, sem overlay de conclusao. Repetir-um
  funciona pelo D-pad (engrenagem -> Repetir -> Repetir item).
- **ERROS.** Zero FATAL/excecao Dart na janela; so linhas
  transitorias do mpv no arranque (`file cache`, `surface NULL`
  no mediacodec), sem impacto visivel.
- **RESUME.** Posicoes 2:17 (link) e 1:12 (loop) salvas e exibidas
  nos cartoes apos voltar. Retomar item concluido (progresso cheio)
  conclui de novo em segundos: reaproveitar do fim em vez de
  recomecar (backlog nao bloqueante).
- **AMBIENTE.** adb caiu 1x com `device offline`: servidor adb local
  travado, nao a TV (ping ok); `kill-server` + reconectar resolveu.

### Barra compacta -- TCL 50" (422/422) -- 12/10/2026

- **MOTIVO.** Painel de 545,6 px logicos (~57% do viewport 960x540)
  ainda grande visualmente; trilho de volume sempre visivel.
- **FIX.** `TvPlayerControls`: 50% ate 460 (440 reais via o teto 880
  da tela), botoes de 44 com glifos de 36, titulo/tempo em caption
  (14), slider de progresso 24 + anel slim, sem trilho de volume
  (so o mudo; volume por cima/baixo com a barra oculta), sem chips.
  Desktop pixel a pixel (parametros opcionais com default).
- **PROVA (ui_compact_bar + tv_compact_bar.png).** Pausado em x36xhzz
  2:17/10:34: painel 876x246 fisicos = 438x123 logicos (45,6% do
  viewport); botoes 88x88 = 44; slider 24; titulo/tempo 19 de altura;
  gaps/padding 12. Foco no Reproduzir apos pausar. So titulo,
  progresso, mudo, voltar 10, play/pausa, avancar 10 e Opcoes.
- **VALIDACAO VISUAL PENDENTE.** Captura enviada; tarefa NAO aprovada
  ate o veredito do usuario. Diagnostico/celular parados.

### Botoes 40 + Opcoes confortavel -- TCL 50" (425/425) -- 12/10/2026

- **MOTIVO.** Botoes de 44 e glifos de 36 ainda exagerados; painel de
  Opcoes com linhas de 52 estourava o topo (Idioma cortada).
- **FIX.** Barra e cantos: botoes de 40 com glifos de 28 (D-pad nao
  precisa de alvo de toque). Painel: densidade vertical -3 (piso 48
  do ListTile denso cai), linhas de 40 em uma linha, chips e espacos
  reduzidos, teto pela ancora (ancora - 72) com rolagem de seguranca.
  Desktop pixel a pixel (overrides so na TV).
- **PROVA (ui_compact_options + tv_compact_bar2/opt3.png).** Barra
  876x238 = 438x119; botoes/cantos 80x80 = 40. Painel 680x738 =
  340x369 (topo y=162, sem corte); 6 linhas de 80 = 40; chips 36;
  Fechar alcancavel. Foco no Pausar/Reproduzir apos acoes.
- **VALIDACAO VISUAL PENDENTE.** Capturas enviadas; tarefa NAO
  aprovada ate o veredito do usuario.

### Opcoes mais baixo -- TCL 50" (425/425) -- 12/10/2026

- **MOTIVO.** Painel de 369 ainda alto; icones em 28 quase perfeitos
  (mantidos), barra em 438x119 mantida.
- **FIX.** Painel: densidade vertical -4, respiro 4, chips 5, Fechar
  6. So TV; desktop em 52/467 intacto.
- **PROVA (ui_compact_options2 + tv_compact_options2.png).** Painel
  680x670 = 340x335 (topo y=230); 6 linhas de 72 = 36; chips 32.
- **VALIDACAO VISUAL PENDENTE.** Captura enviada; tarefa NAO aprovada
  ate o veredito do usuario.

### Letras e icones menores -- TCL 50" (425/425) -- 12/10/2026

- **MOTIVO.** Icones e letras ainda grandes no player; na principal,
  cartoes, selecao e botoes de link grandes. Foto do usuario anexada.
- **FIX (so TV).** Escala de texto minima 1.0 (era 1.1/1.15/1.25);
  icones primario 24/28/32 e secundario 18/20/24; tema tvMode 28;
  barra e cantos com glifos de 24; botoes 48/48/56; miniaturas
  96x56, 112x64 e 128x72. Desktop intacto.
- **PROVA (ui_home_small + tv_home_small/bar3/opt3.png).** Cartoes
  224 de altura (eram 238); Abrir arquivo/link 96 = 48 (eram 112);
  barra 438x~116; painel 5-6 linhas de 36. Link x36xhzz caiu de novo
  (sem conexao); capturas do player com tv long local.
- **VALIDACAO VISUAL PENDENTE.** Capturas enviadas; tarefa NAO
  aprovada ate o veredito do usuario.

### Mais uma volta + progresso fino -- TCL 50" (425/425) -- 12/10/2026

- **MOTIVO.** Pedido do usuario: diminuir tudo so mais uma vez no
  player e na principal; o trilho de progresso estava grosso.
- **FIX (so TV).** Barra/cantos: botoes de 36 com glifos de 20
  (respiro 8). Slider de progresso: trilho fino 4, dedao 10, halo
  12 (slider 24, sem trilho de volume). Painel: densidade -4,
  linhas de 34, teto pela ancora com rolagem de seguranca.
  Tokens: icones 20/24/28 e 16/18/20, caption 12, altura 44/44/52,
  escala minima de texto 1.0, miniaturas 96x56/96x56/112x64,
  tema tvMode 24. Desktop pixel a pixel.
- **PROVA (tv_home_v6/bar_v6/options_v6.png).** Principal enxuta
  (cartoes compactos, Abrir arquivo/link 48); barra fina com
  progresso fino e 5 botoes pequenos; painel de Opcoes compacto
  (Idioma, Legendas, Repetir, Girar, velocidade, informacoes,
  Fechar) sem corte. `tv long` local (link x36xhzz instavel).
- **VALIDACAO VISUAL PENDENTE.** Capturas enviadas; tarefa NAO
  aprovada ate o veredito do usuario. Diagnostico/celular parados.

### Trilho extra-fino -- TCL 50" (426/426) -- 12/10/2026

- **MOTIVO.** Usuario aprovou o restante; so o trilho de progresso
  ainda parecia grosso.
- **FIX (so TV).** Slider da barra: trilho 3 (era 4), dedao 8
  (era 10), halo 10 (era 12); slider 20 (era 24). Trava nova em
  teste para nao regredir. Desktop pixel a pixel.
- **PROVA (tv_bar_v7.png).** `tv long` local com a barra visivel:
  linha de progresso visivelmente mais fina, dedao proporcional,
  resto identico ao aprovado.
- **APROVADO (resto).** Principal, barra, botoes, painel de Opcoes,
  letras e icones: aprovados pelo usuario nesta volta.
- **CONFIGS FINAIS DO PERFIL TV (so TV; desktop intacto).**
  - Barra: 50% ate 460 (440 reais na TCL 960x540); altura
    105-125; botoes 36 com glifos 20; titulo/tempo caption 12.
  - Progresso: trilho 3, dedao 8, halo 10, slider 20; sem trilho
    de volume (so o mudo; volume por cima/baixo com a barra
    oculta); sem chips.
  - Painel de Opcoes: densidade -4, linhas 34, teto pela ancora
    (ancora - 72) com rolagem de seguranca.
  - Tokens compacto/normal/grande: icones 20/24/28 e 16/18/20;
    titulo 20/22/24, corpo 15/17/19, caption 12/12/13; altura
    44/44/52; anel 3/3/4; miniaturas 96x56/96x56/112x64;
    escala minima de texto 1.0 (sistema respeitado ate o maximo);
    tema tvMode 24.

### Concluido solido -- TCL 50" (428/428) -- 12/10/2026

- **MOTIVO.** Foto do usuario: card "Reproducao concluida" com fundo
  preto 0.7 deixava o video atravessar e sumia com os botoes.
- **FIX.** Card solido na cor do painel de Opcoes (0xFF232326),
  nos DOIS modos: blur fica so na barra do player (unico
  BackdropFilter do app alem da barra desktop), resto normal. Na
  TV, o card entrou no padrao compacto: titulo corpo 17 w600,
  "A seguir" caption 12, padding 16/12, raio do token (16),
  gaps 8, borda branca 0.08; botoes ja estavam no padrao (alvo
  minimo 44 dos tokens via FocusableButton). No desktop, SO a
  cor mudou: padding 20/16, raio 12, gaps 12 e tipografia padrao
  intactos, pixel a pixel.
- **PROVA (tv_completed_v8.png).** `sample` local ate o fim: card
  opaco e legivel (titulo, A seguir, 4 botoes com Rever focado),
  zero vazamento do video. Travas novas: solido + compacto na TV,
  solido + dimensoes no desktop.
- **VALIDACAO VISUAL PENDENTE.** Captura enviada; tarefa NAO
  aprovada ate o veredito do usuario.

### Rotulos do painel com cor explicita (429/429) -- 12/10/2026

- **MOTIVO.** Print do usuario no Windows: rotulos do painel de
  Opcoes invisiveis (luminancia 36 = fundo 35), valores claros.
  Codigo atual provado correto em 4 reproducoes (sonda de estilo,
  app real, pixels sobre home e sobre player): o print veio de
  outro build/estado. Padronizacao para a classe de bug sumir.
- **FIX (desktop + TV, pixel identico).** Titulos das linhas
  (`_NavRow`, `_RotateRow`) e cabecalhos (velocidade, submenu)
  com `color: primaryText` explicita em vez de herdar do tema;
  tamanhos seguem herdados. Trava nova sob tema claro hostil.
- **PROVA.** 429/429 + analyze limpo. Pixels do app atual sobre o
  player: rotulos claros e legiveis.

### Lento na TV: 1080p acima do SoC (diagnostico) -- 12/10/2026

- **SINTOMA (TV, nao Windows).** `x36xhzz` em camera lenta na TCL.
  Medido: posicao avancou ~9 s em 64 s de relogio (0,14x);
  resume de 1:16 caiu para ~8 s.
- **CAUSA PROVADA (logcat).** mpv escolheu a variante 1080p fhd
  (6,2 Mbps); hwdec mediacodec-copy OK (OMX.realtek); VO gpu com
  shaders no Mali-470/GLES2; video parado em ~8 s com audio 29 s
  a frente ("delaying audio start"); mpv sugere `--profile=fast`.
  Rede entrega 8,68 Mbps (acima dos 6,2) e 720p local roda ~1x
  pelo mesmo pipeline: gargalo e o render 1080p (copia por CPU +
  upload + shaders a 30 fps) no SoC fraco, nao rede nem decode.
- **LIMITACAO.** media_kit 1.2.6 nao expoe opcoes do mpv
  (sem hls-bitrate/profile/framedrop). Proposta de fix no app:
  detectar master HLS e abrir direto a variante <=720p na TV
  (pendente de decisao: teto automatico x escolha do usuario).
- **SECUNDARIO.** Seek de resume para 1:16 virou seek-to-0 interno
  do mpv (faixa 10-14 s em cache; alvo fora dela); mesmo SoC fraco
  e suspeito. Revalidar apos o teto de variante.

### Teto HLS por classe (447/447) -- TCL 50" -- 12/10/2026

- **FIX (votado: teto auto por classe).** Novo
  `lib/core/utils/hls_variants.dart`: na abertura, TV compacta e
  normal (largura <1280) resolve master HLS e abre direto a melhor
  variante <=720p e <=500 kbps (sem `RESOLUTION`, so a banda
  decide; nada no teto = a mais leve); TV grande, desktop,
  playlist simples, falha/timeout e URL nao-.m3u8 seguem no
  original. Item salvo segue o master (variante expira). Gate sem
  inherited widget (pref + largura da view; `_open` roda no
  initState). 16 testes novos (parse/pick/resolve + fiação).
- **MEDICOES (x36xhzz na TCL, posicao vs relogio).** 1080p60 =
  0,14x (video parado, audio 29 s a frente); 720p60 = 0,33x;
  480p60 = 0,6-0,8x; **380p30 = 1,03x**. Rede entrega 8,68 Mbps,
  demuxer corre a frente, cache cheio, CPU 62% com main thread
  mais quente: gargalo e px/s no pipeline (copia+upload+shaders
  no Mali-470), nao rede. Razao escala com Mpx/s.
- **PROVA (tv_hls_capped.png).** 403 s -> 477,5 s em 80 s de parede
  (1,03x), frame 380p legivel, barra compacta intacta.
- **PENDENTE.** Select manual de qualidade HLS (linha Qualidade
  hoje so lista faixas mpv, 1 no HLS) e revalidar resume apos seek
  longo em HLS com SoC fraco.

### Soak 21 min com teto HLS -- TCL 50" -- 12/10/2026

- **ROTEIRO (x36xhzz, 380p).** Play 184 s ate concluir #1; replay +
  150 s; pausa 46 s (4 frames byte-identicos, MD5 igual); resume +
  60 s ate concluir #2; replay + seeks D-pad -10/+10/+10 sem erro;
  BACK + reabertura + 34 s; BACK final. Parede total ~21 min.
- **RESULTADO.** Reproducao 1x estavel o tempo todo (2 conclusoes
  no ritmo: 477->634 e 575->634); pausa segura; seeks sem erro;
  reabertura retoma; historico sao (posicao sobe, accessedAt
  fresco, percent coerente, completed=false no meio).
- **ERROS.** Zero excecao de app, zero timeout/falha do supervisor,
  zero overlay de erro. So o trio benigno conhecido por abertura:
  "Failed to create file cache", mediacodec surface-NULL
  transitorio e aac env_facs_q invalido (HE-AAC toca normal).
- **ACHADO.** Resume em HLS impreciso no SoC fraco: alem do undershoot
  anterior (1:16 -> ~8 s), um overshoot de ~50 s (reabertura caiu
  ~50 s a frente do salvo; playback 1x normal do ponto errado).
  Seek HLS de 10 s + demuxer fraco = mira instavel. Item de backlog:
  revalidar resume apos seek longo em HLS (pendente).
- **PROVAS.** soak_completed1/replay/paused/seeks.png.

### F5 limpo Windows (rotulos) -- 12/10/2026

- **PROTOCOLO.** App fechado; `flutter clean` + `flutter pub get` +
  `flutter run -d windows` (gancho temp `diag.f5nav` so para navegar;
  revertido apos). Sem alteracao de tema.
- **VEREDITO.** Rotulos legiveis na Home (titulos, cards, estado),
  na barra do player (nome, tempo) e no painel (Idioma, Legendas,
  Repetir, Qualidade, Girar, Velocidade, Fechar): textos claros.
  Home conferida por captura; barra+painel confirmados pelo usuario
  na tela (disputa de foco com video fullscreen no Brave impediu
  captura remota da barra).
- **CONCLUSAO.** O escurecimento anterior era estado de build/cache,
  nao codigo/tema. Nada a alterar no tema. Ganchos revertidos;
  447/447 testes + analyze limpo apos reversao.

### Menus compactos (574/574) -- 18/10/2026

- **MOTIVO.** Usuario: player confortavel, mas menus/configuracoes
  ainda "estourados" na TCL (tema 10-foot generico: appbar 72,
  icones 32, linhas Material de 56-72, titulos 22).
- **FIX (so TV, so telas do AppShell).** `PlayerTheme.tvMenus` por
  classe: appbar 48/52/60 (titulo 18/19/21), icones 20/22/24,
  ListTile densidade -4 com titulo 13/14/16 e subtitulo 12/12/14,
  titleLarge 18/20/22, titleMedium 14/15/17, slider 3/8 (igual a
  barra aprovada), divisor branco 10%; dialogos 18/14; respiro
  vertical do AppShell 8; cabecalhos de secao mais justos.
  Interruptores: `TvSwitchTheme` troca o Switch M3 (52x32 fixo,
  trilho azul cheio) pelo desenho compacto 33x14 em cores neutras.
  Player e painel de Opcoes intactos (nao usam o AppShell);
  desktop pixel a pixel.
- **PROVA (TCL, IP agora 192.168.1.4).** Linhas de configuracoes
  caíram de ~64 para ~56 logicos; letras aprovadas pelo usuario;
  switches compactos pendentes de veredito.

### Saida direta MediaCodec: 1080p a 1x -- TCL 50" (574/574) -- 18/10/2026

- **SINTOMA.** Usuario: Big Buck Bunny trava na TV, roda no PC.
  (O link do bucket Google do feed de exemplo hoje responde 403;
  o feed do sandbox Manus esta fora do ar. Reproduzido com o clipe
  oficial de teste `test-videos.co.uk` 1080p60 e com a variante
  1080p do Mux.)
- **MEDIDO ANTES.** Bunny 1080p60 (10 s): 0:04,7 apos 113 s de
  relogio (~0,04x); `screencap` levava ~20 s (TV saturada).
  Mesma causa do HLS 1080p (0,14x): `vo=gpu` + `mediacodec-copy`
  copia cada quadro para a CPU e redesenha com shaders no
  Mali-470/GLES2.
- **FIX.** Android usa `MediaKitPlayerService.androidDirectOutput`
  (`vo=mediacodec_embed`, `hwdec=mediacodec`): o decodificador
  desenha direto na superficie. Desktop no padrao do media_kit.
  Legendas (SubtitleView) e Girar (RotatedBox) sao do Flutter e
  nao dependem da saida.
- **FALLBACK.** Codec sem decodificador de hardware (provado com
  Theora gerado no PC) dava audio com tela preta. O servico ouve o
  erro `autoconvert: Failed to create HW uploader` (nivel error,
  chega em release), troca para `vo=gpu` + `mediacodec-copy` no
  mesmo arquivo e reseleciona a trilha (`vid` no -> auto); o
  proximo `open` restaura a saida direta.
- **PROVA (TCL, logcat + capturas).** Bunny 1080p60: 10 s em
  10,07 s de relogio (`VO: [mediacodec_embed]`). Mux 1080p direto
  (6,2 Mbps, com audio): posicao 71,0 s apos 70,9 s de
  reproducao (1,00x; antes 0,14x). Theora: imagem visivel no modo
  compativel; Bunny em seguida voltou a saida direta (1,0x).
- **NOTA.** `NativePlayer.setProperty` e publico no media_kit 1.2.6
  (o BACKLOG dizia o contrario): estilo de legenda via `sub-*`
  pode ser viavel sem ponte nativa.
- **NAO VERIFICADO NA TV.** Legenda externa com a saida direta e
  troca de faixa de video em arquivo multi-video.

### Escapes da saida direta (584/584) -- 18/10/2026

- **PREFERENCIA.** Configuracoes > Reproducao > "Modo de video
  compativel" (so Android; vale ao reabrir). Provado na TCL: ligada
  -> `VO: [gpu]`; desligada -> `VO: [mediacodec_embed]`.
- **GUARDA POR APARELHO.** `VideoOutputGuard` (arquivo
  `video_output_guard.json`): marca so enquanto o video toca com a
  saida direta; 2 quedas nativas seguidas com a marca ligada ligam o
  modo compativel de vez naquele aparelho (a opcao mostra "Ligado
  sozinho apos falhas"; desligar zera). Provado na TCL: tocando ->
  `playing:true`; Home -> `onStop` desmarca e o app pausa; BACK do
  player (que so pausa) -> desmarcado. 10 testes novos
  (`test/video_output_guard_test.dart`).
- **ROTEIRO.** `docs/VALIDACAO_APARELHOS.md`: matriz de codecs e de
  telas para Google TV, Fire TV/Mi Box, celular e Windows.

## Trilho do player: cima e baixo saem dele (0.3.0+20)

- Achado do usuário na TCL: com o foco no trilho de progresso, a seta
  para baixo (a caminho de Pausar, voltar ou menu) fazia o vídeo voltar,
  e a seta para cima o fazia avançar. O `Slider` do Flutter, no modo de
  navegação tradicional, usa as quatro setas para ajustar.
- Correção: na TV, o `ExitSlider` coloca o trilho em
  `NavigationMode.directional`. Só esquerda e direita avançam e voltam;
  cima e baixo saem do trilho. OK continua levando para os botões.
- Desktop e celular sem mudança. Teste: `test/tv_slider_exit_test.dart`.
