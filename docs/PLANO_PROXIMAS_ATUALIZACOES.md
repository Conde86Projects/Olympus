# Plano das próximas atualizações (snapshot de pesquisa)

> **Atualização após a v0.3.0 (31/10/2026):** a tabela abaixo é o retrato de antes
> dessa versão. Entraram na 0.3.0: U01, U02, U05, U06 (não reproduzido), U07, U11,
> U13 a U18, U30 e U32. U09 ficou validado só em um PC. Seguem abertos: U08, U10,
> U19 a U21, U25, U27 a U29 e U31. Pacote Android definido depois da 0.3.0:
> `com.conde86.olympus`; instala separado do antigo e não leva os dados salvos.

Data: 2026-10-31
Repositório: `player` (app Flutter "Olympus"), branch `main`, HEAD `c39140a`.

Análise somente leitura. Nenhum código ou arquivo existente foi alterado, e nenhum build ou teste foi executado. Documentos lidos: `docs/BACKLOG.md`, `docs/Olympus.md`, `docs/SITUACAO_ATUAL.md`, `docs/RELEASE_RC1_0.3.0_CHECKLIST.md`, `docs/adr/0001-volume-por-plataforma.md`, `docs/adr/0002-fase-3-mobile.md`, `GLOSSARY.md`, `docs/agents/*.md`. A verificação de estado foi feita com Grep/Read/git e com a lista de issues abertas (`gh issue list`). Contagens de testes são estáticas (`test(`/`testWidgets(` em `test/`) e não foram executadas.

Estado final de cada item: "feito" = código e teste verificados; "parcial" = parte no código, falta validação ou parte da escopo; "pendente" = sem implementação; "bloqueado" = depende de dado ou decisão externa; "congelado" = limitação aceita.

---

## 1. Itens planejados ou pendentes

| ID | Título | Origem (arquivo e seção) | Estado | Dependências |
|----|--------|--------------------------|--------|--------------|
| U01 | Estilo visual das legendas (tamanho, cor, fundo, posição) | BACKLOG "Estilo visual das legendas" (l.6-25); Olympus "Futuro" (l.449); SITUACAO §4 (l.170-171) | pendente (tecnicamente desbloqueado) | D3 (valores visuais); spike de viabilidade |
| U02 | Stall de rede: erro com "tentar de novo" e timeout visível | BACKLOG "Não bloqueante" (l.189-193); SITUACAO §4 (l.175-176) | parcial | Teste em aparelho com rede lenta (U13) |
| U03 | Miniaturas órfãs ao remover itens | BACKLOG "Incorporado (miniaturas)" (l.122-124); SITUACAO §2 (l.79) e §4 (l.172) | feito no código (docs desatualizados) | Confirmar órfãos de falha de geração (não coberto) |
| U04 | Item concluído reabre do início ("Ver de novo") | BACKLOG "Não bloqueante" (l.179-181); SITUACAO §4 (l.173-174) | feito no código; validar no aparelho | Caso "sair sem assistir" no aparelho (U14 e F2) |
| U05 | `startInFullscreen` no celular | SITUACAO §4 (l.181) "lacuna conhecida"; Olympus §Estado | feito no código (docs desatualizados) | Confirmar teste dedicado (sem achado por grep) |
| U06 | Vídeo local aberto pelo caminho digitado não fixa na biblioteca | SITUACAO §4 (l.186-188) | pendente (causa aberta) | Reprodução na TCL |
| U07 | Diálogo de fim de reprodução na TCL | SITUACAO §4 (l.195-197) | parcial (código existe; falta validar na TCL) | Aparelho TCL e vídeo até o fim |
| U08 | Crash nativo no FinalizerDaemon (`SurfaceTexture.release`) | SITUACAO §4 (l.198-204) | congelado | Upgrade do media_kit_video (sem `dispose()` no VideoController) |
| U09 | hwdec por software no PC de dev (avaliar 4K) | BACKLOG (l.182-188); SITUACAO §4 (l.180) | pendente | D7; vídeo 4K para medir |
| U10 | Validação de frames e modelo de TV física (§24.8); AVD-TV com EGL quebrado | BACKLOG "Limitações conhecidas (Checkpoint TV)" (l.104-110) e "Completo" (l.158-165); SITUACAO §4 (l.178) | pendente | D4; TV física |
| U11 | Investigar aquecimento da detecção fria de variantes HLS | BACKLOG (l.237-243) | pendente (investigação, sem bloqueio) | Nenhuma |
| U12 | Seek pós-troca de variante em mpv frio (falha da RC2) | BACKLOG (l.244-252) e resolução (l.253-259) | feito (validado na TCL em 13/10) | Nenhuma; remover o item aberto do texto |
| U13 | Smoke RC1 no celular: retrato, paisagem, tela cheia | RC1 checklist (l.52, l.53, l.61) | pendente | Celular físico |
| U14 | Smoke RC1 na TCL: versionName 0.3.0-rc.1 | RC1 checklist (l.70) | pendente | TCL |
| U15 | Smoke RC1 no Windows: janela normal, pequena, minimizar, X, mudo, persistência, catálogo, reprodução, retomada | RC1 checklist (l.93-101); ticket #4 fechado | pendente | PC de dev e uso do usuário |
| U16 | Validação do volume por plataforma (mudo nas 3 plataformas, fileira no Windows) | BACKLOG "Volume" (l.290-291); RC1 checklist (l.55, l.97) | parcial (celular e TCL feitos; mudo no Windows pendente) | U15 |
| U17 | Tag e checklist da RC1 (base e commit) | RC1 checklist (l.4-5, l.45, l.103-107) | parcial (tag existe) | D1 |
| U18 | Build number do pubspec (`+1002` vs `+1` no checklist) | RC1 checklist (l.9); `pubspec.yaml:4` | pendente | D1 |
| U19 | Fonte real (novo adaptador em `lib/services/sources/`) | BACKLOG "Fora da fase atual" (l.76-78); Olympus "Política de fontes reais" (l.463-486) | bloqueado | D5 (URL, formato, exemplo JSON, auth, autorização) |
| U20 | Qualidade dinâmica em fontes reais | Olympus "Futuro" (l.451) | bloqueado | U19 |
| U21 | Fontes autorizadas reais, catálogo e autenticação | Olympus "Futuro" (l.455-456); BACKLOG (l.76-78, `account.login`) | bloqueado | U19; D5 |
| U22 | Modo seguro | Olympus "Futuro" (l.452) | feito (`DiagnosticsScreen`, `test/safe_mode_test.dart`) | Nenhuma |
| U23 | Diagnóstico e exportação de logs sem credenciais | Olympus "Futuro" (l.453) | feito ("Exportar relatório" em `lib/features/diagnostics/diagnostics_screen.dart:296`; `lib/services/diagnostics_service.dart:171`) | Nenhuma |
| U24 | Atualizações controladas de add-ons | Olympus "Futuro" (l.454); BACKLOG "Incorporado" (l.85-90, Task 10) | feito (`test/addon_updates_test.dart`) | Checagem manual aceita (U31) |
| U25 | Assinatura de pacotes | Olympus "Futuro" (l.458); Olympus §Fontes desconhecidas (l.263); BACKLOG (l.139-141) | pendente (futuro) | D6 |
| U26 | Validação física em Smart TV e TV Box | Olympus "Próxima etapa" item 8 (l.445) e "Futuro" (l.457) | parcial (TCL validada em 0.2.0 e RC1) | TV física (U10) |
| U27 | Suporte a outras plataformas de TV (Tizen) | Olympus "Futuro" (l.459); BACKLOG (l.106); SITUACAO §4 (l.177) | pendente / fora | D8; sem alvo Flutter oficial |
| U28 | Miniaturas mais avançadas | Olympus "Futuro" (l.450) | pendente (escopo indefinido) | D9 |
| U29 | compileSdk fixo em 36 (file_picker) | BACKLOG (l.106-108); SITUACAO §4 (l.179) | pendente | Upgrade do Flutter |
| U30 | Flash branco no primeiro screencap da TV | BACKLOG "Não bloqueante" (l.169-172) | pendente (cosmético, sem bloqueio) | Nenhuma |
| U31 | Checagem de updates em segundo plano | BACKLOG (l.148-150) | congelado (aceito: checagem manual) | D10 |
| U32 | Issue #1 aberta: "BBB definitivo como HLS multivariante" | `gh issue list` (issue #1, label `ready-for-agent`) | feito no código (issue deve ser fechada) | D2 |

Observação: BACKLOG "Fora da fase atual (confirmado)" (l.27-78) mistura itens concluídos e pendentes sob o mesmo título. Esta tabela considera o estado real de cada um.

---

## 2. Fatias

Ordem por valor e risco. Cada fatia pode ser entregue e testada sozinha.

### F1. Higiene de documentação e RC1 (sem código)
- **Objetivo:** alinhar os documentos ao estado real antes de qualquer trabalho novo.
- **Itens:** U17, U18 (decisão), correções da seção 5 deste plano, U32 (fechar issue #1 se confirmado).
- **Teste de aceite:** `grep` dos números de versão e de testes nos documentos bate com `pubspec.yaml:4` e `lib/core/constants/app_constants.dart:50`; `git tag` aponta para o commit documentado no checklist.
- **Riscos:** baixo. Risco de reescrever checklists que o usuário usa como registro de validação. Alterar só com ordem explícita.

### F2. Fechar pendências de validação já implementadas
- **Objetivo:** confirmar no aparelho o que o código já faz.
- **Itens:** U04 (concluído e "sair sem assistir"), U07 (diálogo de fim na TCL), U16 (mudo no Windows).
- **Teste de aceite:** checklist manual na TCL e no Windows; teste automatizado já existe para U04 (`test/completed_replay_test.dart`).
- **Riscos:** depende de vídeo que chega ao fim na TCL. Sem achado, o item continua aberto.

### F3. Smoke da RC1 nos aparelhos
- **Objetivo:** fechar o checklist RC1 (U13, U14, U15).
- **Teste de aceite:** todos os `[ ]` de `docs/RELEASE_RC1_0.3.0_CHECKLIST.md` marcados com evidência (SHA do APK e versionName via `dumpsys`, conforme o próprio checklist).
- **Riscos:** exige tempo do usuário em três equipamentos. Não há código a mudar.

### F4. Stall de rede: erro visível e "tentar de novo" (U02)
- **Objetivo:** trocar o "Cancelar" eterno por erro com nova tentativa.
- **Estado atual:** `bufferTimeout` de 15 s em `lib/core/constants/app_constants.dart:62` já dispara `_fail(PlaybackErrorKind.timeout)` em `lib/services/supervised_player_service.dart:254-258`. Não há `network-timeout` no mpv (busca sem resultado em `lib/`).
- **Itens:** confirmar a mensagem de erro com "tentar de novo" para timeout de buffering; avaliar `network-timeout` via `NativePlayer.setProperty` (`lib/services/media_kit_player_service.dart:147`).
- **Teste de aceite:** teste de widget com player falso que fica em `buffering` além de `bufferTimeout` e espera erro com ação de nova tentativa (usar o relógio fake, como em `test/mobile_chrome_test.dart`). Aparelho: limitar a rede e observar.
- **Riscos:** timeout curto demais derruba fontes lentas mas válidas. O valor de 15 s exige decisão (D11).

### F5. Vídeo local não fixa na biblioteca (U06)
- **Objetivo:** achar a causa do caminho digitado não entrar na biblioteca.
- **Estado atual:** `lib/features/open_media/open_media_screen.dart:282-286` chama `library.upsert(item)` e `ThumbnailService.backfill`. A causa não está no código lido.
- **Teste de aceite:** teste de widget que abre um caminho local e verifica o item na biblioteca após `upsert`; depois, reprodução na TCL.
- **Riscos:** causa desconhecida; pode ser de navegação, de persistência ou de chave de ID. Fazer diagnóstico antes de corrigir.

### F6. Estilo de legendas (U01)
- **Objetivo:** tamanho, cor, fundo e posição de legenda.
- **Estado atual:** `NativePlayer` já é usado (`lib/services/media_kit_player_service.dart:147`, `setProperty` em :160 e :173). Nenhuma propriedade `sub-*` é aplicada (busca em `lib/`). O BACKLOG (l.17-21) diz que a API não expõe `sub-*`, e l.23-25 pede reavaliação: o código atual já contraria a premissa.
- **Itens:** spike de `sub-font-size`, `sub-color`, `sub-back-color`, `sub-pos`; depois, tela de ajustes e persistência.
- **Teste de aceite:** teste unitário que verifica o mapa de propriedades enviado (com `NativePlayer` falso) e checagem visual no Windows; no Android, passar pelo caminho `mediacodec` direto (`media_kit_player_service.dart:125`, :160).
- **Riscos:** no Android a saída direta pode ignorar legendas do mpv. Valores de cor e posição precisam de decisão visual (D3). Ler `docs/PADROES_VISUAIS.md` antes.

### F7. hwdec em 4K (U09)
- **Objetivo:** decidir entre forçar `d3d11va`/`dxva2` ou atualizar driver/ANGLE.
- **Teste de aceite:** reprodução de vídeo 4K no PC de dev com contagem de quadros perdidos no log do mpv; sem 4K, o item não fecha.
- **Riscos:** depende de hardware e driver; mudar `hwdec` pode regredir 1080p.

### F8. Pendências menores (U29, U30, U28, U11)
- **Objetivo:** itens de baixo risco, um por vez.
- **Teste de aceite:** U29: `flutter build apk` com compileSdk novo (só no upgrade do Flutter). U30: checagem de tela no primeiro arranque frio. U28: escopo a definir (D9). U11: métricas de aquecimento do HLS frio sem alterar histórico.
- **Riscos:** baixos; U28 sem escopo pode crescer.

### F9. Fontes reais (U19, U20, U21) — bloqueada
- **Objetivo:** primeiro adaptador real em `lib/services/sources/<nome>_source.dart`.
- **Pré-requisito:** D5 completo (Olympus §"Política de fontes reais", l.463-476).
- **Teste de aceite:** testes de sucesso, erro, cancelamento e recuperação (Olympus §Testes, l.378) e SSRF já cobertos pela barreira existente.
- **Riscos:** autenticação e termos de uso do serviço; o projeto proíbe contornar restrições (Olympus l.486).

### F10. Assinatura de pacotes (U25) — fora do ciclo
- **Objetivo:** política de assinatura, checksum e sandbox antes de qualquer código executável.
- **Riscos:** alto. Não iniciar sem D6.

---

## 3. Decisões pendentes do usuário

- **D1. Qual commit é a RC1?** O checklist diz base `e4e4579` e tag `d7a80fd` (l.4-5, l.45). Pelo git, a tag `v0.3.0-rc.1` aponta para o commit `260f340` ("configura skills"). `e4e4579` não é ancestral de `088f15c`. Decidir se a tag fica como está ou se é recriada (U17).
- **D2. Fechar a issue #1** ("BBB definitivo como HLS multivariante") no GitHub: o trabalho consta como feito (BACKLOG l.34-38; RC1 l.82). Ação de publicação, requer confirmação explícita.
- **D3. Valores visuais das legendas** (tamanho, cor, fundo, posição) e se o padrão segue `docs/PADROES_VISUAIS.md` (U01).
- **D4. Modelo de TV física** para validação de frames (§24.8, BACKLOG l.108) e se há TV para comprar ou emprestar (U10).
- **D5. Fonte real:** URL, formato de resposta, exemplo JSON, autenticação, cabeçalhos, paginação, tipos de conteúdo e confirmação de autorização (Olympus l.467-476; U19-U21).
- **D6. Assinatura de pacotes:** entra no roadmap ou fica como futuro distante (U25).
- **D7. hwdec:** forçar `d3d11va`/`dxva2` ou só atualizar driver/ANGLE (U09).
- **D8. Tizen:** continua fora do escopo? (U27).
- **D9. Miniaturas avançadas:** qual é o escopo (U28)?
- **D10. Checagem de updates de add-ons:** manter só manual ou agendar em segundo plano (U31)?
- **D11. Timeout de buffering:** manter 15 s ou ajustar (F4).

---

## 4. Resumo por estado

- Feito no código, falta validar no aparelho: U04, U07, U16 (parte), U26.
- Feito no código, docs desatualizados: U03, U05, U12, U22, U23, U24, U32.
- Parcial: U02, U17, U26.
- Pendente: U01, U06, U09, U10, U11, U13, U14, U15, U18, U28, U29, U30, U25, U27.
- Bloqueado por dado ou decisão: U19, U20, U21.
- Congelado: U08, U31.

---

## 5. Itens desatualizados nos documentos

1. **Versão:** `docs/Olympus.md` l.5 diz `0.2.0`. O `pubspec.yaml:4` diz `0.3.0-rc.1+1002` e `lib/core/constants/app_constants.dart:50` diz `0.3.0-rc.1`.
2. **Contagem de testes (quatro números):** `docs/Olympus.md` l.354 diz 394; `docs/BACKLOG.md` l.31 (504), l.43 (356), l.50 (382), l.54 (394), l.266 (512/512); `docs/RELEASE_RC1_0.3.0_CHECKLIST.md` l.40 (677/677); `docs/NOTAS_2026-10-24.md` l.5 (697). O número 741 citado na tarefa não aparece em `docs/` ou `GLOSSARY.md`. Contagem estática atual: 724 declarações `test(`/`testWidgets(` em 66 arquivos de `test/`. Os números dos documentos são de datas diferentes e não são comparáveis. Recomendo registrar o número real da execução antes de cada release.
3. **Roadmap RC1 em Olympus:** `docs/Olympus.md` l.433-434 ainda mostra "build e teste visual no Windows" e "validação em hardware de TV" como não feitos. O checklist RC1 l.41 registra `flutter build windows: OK` e o `docs/SITUACAO_ATUAL.md` l.62-63 registra validações concluídas.
4. **Próxima etapa:** `docs/Olympus.md` l.438-445 descreve a configuração do Windows como próximo passo, já superada pelos registros acima.
5. **Futuro com itens feitos:** `docs/Olympus.md` l.452 (modo seguro), l.453 (exportação de logs) e l.454 (atualizações de add-ons) já estão implementados (U22-U24).
6. **Caminho do cofre de credenciais:** `docs/Olympus.md` l.185 cita `source_credential_store.dart`. O arquivo real é `lib/services/sources/source_credentials.dart:6` (`abstract class SourceCredentialStore`).
7. **Miniaturas órfãs:** `docs/BACKLOG.md` l.122-124 e `docs/SITUACAO_ATUAL.md` l.172 dizem que órfãos não são apagados. `lib/services/library_service.dart:94` e :104 chamam `ThumbnailService.deleteFor` ao remover ou limpar; há `test/thumbnail_cleanup_test.dart`.
8. **Pôster remoto:** `docs/BACKLOG.md` l.120-121 diz "pôsteres remotos seguem em aberto". O próprio BACKLOG l.50-52 registra pôster remoto com fallback feito.
9. **Item concluído:** `docs/BACKLOG.md` l.179-181 e `docs/SITUACAO_ATUAL.md` l.173-174 tratam "Ver de novo" como pendente. `lib/features/player/player_screen.dart:115` e `test/completed_replay_test.dart` mostram a implementação. `docs/SITUACAO_ATUAL.md` l.47-48 já a descreve como feita.
10. **startInFullscreen:** `docs/SITUACAO_ATUAL.md` l.181 diz "segue lacuna conhecida". `lib/features/player/player_screen.dart:1281-1290` aplica a preferência no celular.
11. **Premissa da legenda:** `docs/BACKLOG.md` l.17-21 diz que o media_kit 1.2.6 não expõe `sub-*`. Na mesma seção, l.23-25 registra que `NativePlayer.setProperty` é público e já usado. O código usa `setProperty` (`lib/services/media_kit_player_service.dart:160`, :173).
12. **Falha de seek da RC2:** `docs/BACKLOG.md` l.244-252 descreve a falha sem marcar resolução. A resolução está em l.253-259 (13/10). Remover ou marcar o primeiro bloco.
13. **Stall de rede:** `docs/SITUACAO_ATUAL.md` l.175-176 diz "falta timeout visível". `lib/services/supervised_player_service.dart:254-258` já converte buffering acima de `bufferTimeout` em erro de timeout. Falta confirmar a interface (U02).
14. **Issue #1:** `gh issue list --state open` mostra a issue #1 "Spec: BBB definitivo como HLS multivariante" aberta com `ready-for-agent`. `docs/BACKLOG.md` l.34-38 e l.194-201 e o checklist RC1 l.82 registram o trabalho como feito. As issues #2, #3, #6, #7 e #8 estão fechadas. A #4 (smoke) também está fechada, mas o smoke RC1 continua aberto (U13-U15). `docs/BACKLOG.md` l.38 ainda aponta "ticket #4" como pendência.
15. **Build number:** `docs/RELEASE_RC1_0.3.0_CHECKLIST.md` l.9 diz `0.3.0-rc.1+1`. O `pubspec.yaml:4` diz `+1002`. Decidir qual vale (D1).
16. **Tag e commit da RC1:** `docs/RELEASE_RC1_0.3.0_CHECKLIST.md` l.4-5 e l.45 citam base `e4e4579` e tag `d7a80fd`. `git rev-list -n1 v0.3.0-rc.1` retorna `260f340`. Ver D1.
17. **Validação de volume:** `docs/BACKLOG.md` l.290-291 pede validar "mudo nas três plataformas e fileira alinhada no Windows" como pendente. `docs/RELEASE_RC1_0.3.0_CHECKLIST.md` l.91 marca a fileira do Windows como validada e l.97 deixa o mudo do Windows aberto. Os dois documentos divergem sobre o que falta.
18. **Cabeçalho do BACKLOG:** "Fora da fase atual (confirmado)" (l.27) lista itens concluídos (5B, 5C, refinamento UX) e pendentes na mesma seção. Separar em "Concluído" e "Pendente".
19. **Glossário e SITUACAO:** `GLOSSARY.md` l.18-19 define "Mutar com o sistema", termo que `docs/SITUACAO_ATUAL.md` l.6-7 não lista entre os termos canônicos. Menor, mas vale incluir.
20. **Volume (fonte única):** a regra de volume aparece em `docs/adr/0001-volume-por-plataforma.md`, `docs/Olympus.md` l.91-118, `docs/BACKLOG.md` l.269-291 e `docs/SITUACAO_ATUAL.md` §2 (l.59-71). O conteúdo é consistente. Mantê-lo em um único lugar (ADR-0001) e linkar dos demais reduz o risco de divergência.
