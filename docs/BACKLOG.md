# Backlog técnico

Itens aceitos como pendentes, sem bloquear a entrega da fase atual.
Decisão registrada em 10/10/2026.

## Estilo visual das legendas (spec §16, parcial)

Seleção e reprodução de legendas funcionam e continuam cobertas por
testes (submenu de legendas nos testes de widget; legenda externa no
teste de integração). Fica pendente só a estilização:

- tamanho da legenda;
- cor da legenda;
- cor/presença do fundo;
- posição na tela.

Motivo: o media_kit 1.2.6 não expõe propriedades do mpv (`sub-font-size`,
`sub-color`, `sub-back-color`, `sub-pos` etc.) pela API Dart — as funções
`_setProperty*` existem só como bindings FFI privados. Implementar exige
uma ponte própria com o mpv nativo (platform channel ou fork da camada
de plataforma), fora do escopo da fase atual.

## Fora da fase atual (confirmado)

- Qualidade dinâmica e retomada HLS (§13): seleção manual,
  política automática e resume HLS concluídos e aprovados na TCL
  (504 testes, analyze limpo; 0.1.0-rc.2). Detalhes nos itens
  abaixo; detecção fria segue como investigação separada, sem
  bloquear a retomada aprovada.
- Fontes autorizadas — Fase 5B pronta (tela adicionar/gerenciar:
  prévia de manifesto/feed, aviso de desconhecida, aprovação
  explícita, salva desativada, editar com reaprovação por origem,
  atualizar catálogo, remover).
- 5C preparação pronta (356 testes): barreira SSRF no fetcher
  (bloqueia localhost/loopback/privados/link-local/multicast/ULA e
  revalida cada redirect, max 3; `allowPrivate` só para testes em
  loopback). Proteções mantidas: HTTP/HTTPS apenas, timeout,
  256 KB por resposta, 500 itens por feed, isolamento por fonte,
  nenhum código executável. Falta o usuário fornecer URL, formato
  da resposta, autenticação e confirmação de autorização.
- 5C UI de fonte pronta (382 testes): pôster remoto no cartão com
  fallback, menu de qualidades da fonte no painel, troca com
  posição/id preservados, tudo dirigido pelos dados (sem dados =
  comportamento anterior).
- Refinamento UX pronto (394 testes, analyze limpo, só adaptador
  demo): rótulo "Qualidade" atualiza ao vivo no diálogo aberto via
  `sourceQualityListenable` (faixas do motor, posição, histórico
  único e URL padrão intactos); falha na troca cai no overlay de
  erro supervisionado com nova tentativa; ESC fecha painel e
  diálogos de editar/remover; TAB+enter alcança Salvar, Cancelar
  da revisão e confirmação de remoção; setas+OK selecionam
  rendição; pôster/miniatura com falha caem no placeholder.
  Estados revisados sem mudança de código: feed vazio, itens
  inválidos, timeout e fonte indisponível (já isolados por fonte
  com mensagens). Nota de teste: a transição erro+painel na mesma
  frame dispara um assert de semântica do framework no binding de
  teste (reproduz sem esta mudança); o teste usa settle até
  `paint`.
- 5C preparação extra pronta: contrato `SourceAdapter`
  + registro, fonte demo realista (`demo_source_adapter.dart`,
  formato próprio/paginação/busca, host `.invalid`, só testes),
  credenciais (`SourceCredentialStore`: memória + keychain via
  `flutter_secure_storage`, sem chaves no código), miniatura e
  qualidades opcionais no item, auth só na origem em redirects.
  Contrato em `docs/FONTES_ADAPTADOR.md`. Nenhum provider real
  conectado; `AddonService`, locais e embutido intactos.
- 5C integração (quando os dados chegarem): novo adaptador em
  `lib/services/sources/` + testes, sem quebrar a suíte.
  Autenticação só via fluxo do serviço (`account.login` declarado).

## Incorporado (spec v0.3, 10/10/2026)

O que era "próxima etapa" foi aplicado e está coberto por testes
(224 testes, analyze limpo):

- gerenciador de add-ons (Tasks 1–6);
- modo seguro + diagnóstico e recuperação (Tasks 7–8);
- timeout/cancelamento/tipos de erro no player (Task 9);
- atualizações controladas com rollback (Task 10);
- idiomas e proveniência (Task 11);
- matriz de reprodução (§22, §26.10) em `test/routes_smoke_test.dart`.

## Incorporado (Fase 4 / TV, 11/10/2026)

- Setas navegam o foco; seek/volume por seta só com controles ocultos;
  foco inicial e restauração de foco; política direcional do player
  (Tasks 12–13, §18, §12.2).
- Modo TV manual: alvos 64 px, texto maior, margem anti-overscan,
  controles persistentes navegando (Task 14, §3.4).
- Shell Android criado + leanback (launcher, features, banner
  provisório); APK debug compila; checklist em
  `docs/VALIDACAO_TV.md` (Task 15).
- Migração file_picker 8 → 13 (exigida pelo compileSdk 36).

## Limitações conhecidas (Checkpoint TV, 11/10/2026)

- Tizen fora: sem alvo Flutter oficial (fork da Samsung).
- Modelo de TV física para validação de frames (§24.8) a decidir
  (AVD headless tem EGL quebrado: decode/relógio OK, frame preto).
- compileSdk fixo em 36 por causa do file_picker (revisar no upgrade
  do Flutter).

## Incorporado (miniaturas, 11/10/2026)

- Miniaturas locais (§15.1): canal `player/thumbnails`
  (MediaMetadataRetriever, frame ~3 s, JPEG ≤320 px) + gravação em
  `<support>/thumbnails/<id>.jpg`; geração ao adicionar e backfill
  ao reproduzir (`ThumbnailService.backfill`); render no card com
  fallback para placeholder; merge do `upsert` preserva/aplica
  `thumbnailPath` (regressão coberta). Links ficam no placeholder
  (pôsteres remotos seguem em aberto). Desktop sem geração
  (MissingPlugin → placeholder). Provado no AVD-TV (t_both.png).
  Limitações: arquivos órfãos não são apagados ao remover itens;
  `Image.file` trava o `flutter test` neste Windows (ramo coberto
  via builder injetável + inspeção sem pump).
- 301 testes, analyze limpo.

## Incorporado (TV launcher + Leanback + validação, 11/10/2026)

- Banner 320x180 (`drawable-xhdpi/tv_banner.png`), provado no
  launcher Google TV; detecção automática Leanback (`player/tv_info`)
  com `tvModeAuto` (manual desliga o auto); validação mínima em
  AVD-TV: render, foco, setas, voltar, seek ±10 exato, controles
  (287 testes, analyze limpo; `docs/VALIDACAO_TV.md`).

## Limitações conhecidas (Checkpoint Completo, 10/10/2026)

Honestas e registradas, sem bloquear a revisão:

- Formato de pacote/assinatura (§24): protótipo valida manifesto JSON
  (+ checksum opcional); assinatura documentada como futura. Nenhum
  add-on executa código — só manifestos e fixtures.
- Classificação de erro mpv é heurística sobre strings nativas
  (frágeis); `desconhecido` é o fallback honesto, nunca um chute.
- Contador de falhas no arranque é conservador no desktop; o modo
  seguro manual está sempre acessível no diagnóstico.
- A suíte usa player em memória + fixtures: decodificação real
  (curta/longa, buffer sob rede instável) precisa de validação em
  aparelho antes de cada versão relevante (§26.15.4).
- Checagem de updates é manual (ao abrir a tela); sem agendamento em
  segundo plano. Rollback de 1 nível (manifesto + estado).
- Idiomas: ~30 códigos mapeados para pt-BR; código desconhecido é
  exibido como está, nunca omitido.
- Garantias por arquitetura (contratos `MediaPlayerService` /
  `AddonService` + fixtures, dispose ao fechar a tela), sem teste
  automatizado dedicado: UI desacoplada de fonte externa (§22),
  ausência de código arbitrário (§22), ausência de vazamento de
  recursos (§23).
- Prova em aparelho da troca de qualidade (spec §13, 11/10/2026):
  implementação completa (modelo + contrato + media_kit + painel,
  linha oculta com ≤1 faixa, 6 testes de widget provando
  exibição/submenu/aplicação). No AVD-TV o mpv lista 2 faixas de
  vídeo e as remove ~15ms depois (MP4 multi-vídeo é fundido em 1;
  MKV 2 vídeos e DASH 2 renditions sofrem o wipe + timeout de carga),
  com `EGL_BAD_ATTRIBUTE` no mesmo milissegundo — o emulador não
  carrega fontes com 2 faixas de vídeo. Exige TV física (§24.8).

## Não bloqueante (Spec 27 aprovada, 12/10/2026)

- Flash branco transitório ao relançar a tela na TV: o primeiro
  `screencap` após instalar/relançar sai branco (~12 KB); uma tecla
  resolve e o app segue normal, sem exceção no logcat. Cosmético e
  raro em uso real (só no arranque frio). Não bloqueia a RC1.
- Link de teste oscilante na sessão (§27.10) não é problema de
  layout: falhou e voltou sozinho; o overlay de erro/fonte se
  comportou corretamente em todas as classes. Sem ação.
- Chips longos da barra TV: ellipsis no valor com rótulo completo
  no tooltip e valor cheio a um OK no subpainel. Comportamento
  travado em teste (`test/tv_layout_test.dart`). Sem ação.
- Retomar item com progresso em 100% conclui em segundos em vez de
  recomeçar do zero (observado no soak com `tv long`). UX menor:
  item concluído deveria reabrir do início. Não bloqueia a RC1.
- hwdec indisponível no PC de dev (12/10/2026): todos os drivers
  falham no log do mpv (d3d11-egl, dxva2-egl com "Failed to create
  EGL surface", d3d11va, dxva2-dxgi, dxva2-dxinterop; Intel Arc B580
  via ANGLE) e o mpv cai para decode por software. Para 1080p30 é
  suficiente (sonda mediu 1.00 cravado em 85 s de `x36xhzz`), mas
  4K pode engasgar: avaliar forçar `d3d11va`/`dxva2` ou atualizar
  driver/ANGLE. Não bloqueia a RC1.
- Stall de rede vira "Cancelar" eterno em vez de erro (12/10/2026):
  fonte lenta mantém o overlay de buffering sem prazo visível; o
  `bufferTimeout` do supervisor existe mas o usuário não vê
  progresso nem ação além de Cancelar. Proposta: timeout de rede
  no mpv + overlay com "tentar de novo". Não bloqueia a RC1.
- Seletor manual de qualidade HLS pronto (12/10/2026): Opções →
  Qualidade lista Automática (padrão, teto da classe inalterado),
  Original (só quando difere da Automática tetada) e apenas as
  variantes reais do master; a troca reabre preservando item,
  histórico e posição aproximada; na TV o acesso é por D-pad → OK
  sem seção permanente na barra compacta; falha da variante cai no
  erro controlado com "Voltar para Automática". Coberto por
  `test/hls_quality_selector_test.dart`.
- Política automática de qualidade por desempenho pronta
  (12/10/2026): perfil por plataforma/Leanback/viewport
  (`HlsVariants.autoDecision`) — TV compacta/normal mantém o teto
  que estabilizou a TCL (≤720p/500 kbps), TV 4K e desktop sem
  teto (desktop nunca é tetado pelo tamanho da janela), TV sem
  viewport cai no teto fraco; MP4 e playlist simples fora da
  política. Na TV em Automática, a capacidade observada
  (posição/relógio < 0,9 na primeira janela) desce um degrau uma
  vez por abertura; override manual nunca é rebaixado e a
  qualidade efetiva aparece no painel ("Automática · 288p" /
  "Efetiva: 288p"). Falha de detecção abre o master. Coberto por
  `test/hls_auto_policy_test.dart`. Sem persistir a decisão além
  da abertura; resume HLS é o item seguinte, separado.
- Resume HLS pronto, 2ª etapa (12/10/2026; era o item separado
  do seletor e da política): só em masters HLS reais. O seek
  inicial espera prontidão real — sair de buffering e observar o
  primeiro avanço de posição, com timeout limitado (~8 s) e seek
  de melhor esforço ao estourar. Após cada seek, a sonda registra
  posição antes, imediatamente depois e após estabilizar; a
  correção (no máximo UMA, sem loop) só vale dentro da tolerância
  de 4 s, validada após pousar. Pouso incorreto: pausa de
  segurança, sem marcar concluído e sem sobrescrever o histórico
  com o ponto errado (vale até nova abertura ou relocalização),
  com o motivo em `resume-fallback` no log técnico. Falha do
  primeiro seek não derruba a abertura; sem duração, a espera
  estoura em silêncio. MP4, playlist simples e falha de detecção
  seguem no fluxo anterior, sem fetch adicional no MP4.
  Política de qualidade, histórico e ID intocados. Coberto por
  `test/hls_resume_test.dart`, `test/hls_resume_probe_test.dart`
  e `test/hls_resume_ready_test.dart`.
- Conclusão HLS na TCL (12/10/2026): retomada aprovada no aparelho
  — o gate de prontidão resolveu a causa raiz (seek após o
  primeiro avanço real, fora de buffering; pouso exato em 2:08,
  correção dispensada, histórico íntegro). Correção limitada e
  sem loops, mantida.
- [Investigação, sem bloqueio] Detecção fria de variantes HLS
  (12/10/2026): no boot com rede fria o fetch do master falha e a
  abertura cai no master pelo fallback (correto e seguro); o teto
  da classe só engaja com a rede pronta. Investigar apenas o
  aquecimento posterior da detecção — sem atrasar a abertura, sem
  reiniciar reprodução e sem alterar histórico/ID. Não bloqueia a
  retomada já aprovada.
- [Falha registrada na RC2, sem bloqueio do que passou] Seek
  pós-troca de variante no mpv frio (12/10/2026, TCL): o seek de
  preservação de posição após reabrir em outra variante falha no
  motor (`error running command _command(seek, …)`) e a reprodução
  recomeça perto de 0 (193 s → ~10 s observados); vale para troca
  manual e para o downgrade do observador. Mesmo mecanismo do
  resume frio, mas no caminho `_switchHlsQuality`/reabertura —
  exige gate de seek antes de reabrir em variante (proposta, sem
  código aplicado).
