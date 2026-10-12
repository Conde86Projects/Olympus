# Tarefas: Add-ons, modo seguro e recuperação

Comandos de verificação: `flutter test <arquivo>` (focado),
`flutter test` (suíte), `dart analyze` (estático).

## Task 1: Modelos de add-on + validação de manifesto ✅

**Description:** Criar `AddonManifest` (id, nome, versão, autor,
descrição, ícone, homepage, repositório, permissões, plataformas,
tipos de conteúdo, updateUrl opcional, aviso legal), `AddonInfo`
(estado: ativo/inativo/atualização/erro + diagnóstico) e
`AddonRepository` (nome, origem, confiança), com `toMap`/`fromMap` e
validador de manifesto (campos obrigatórios, versão semver, permissões
conhecidas, plataformas conhecidas).

**Acceptance criteria:**
- [ ] Manifesto válido passa; inválido (campo ausente, versão ruim,
      permissão desconhecida) falha com motivo em pt-BR
- [ ] Round-trip JSON preserva todos os campos

**Verification:**
- [ ] Tests pass: `flutter test test/addon_models_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** None

**Files likely touched:**
- `lib/models/addon_manifest.dart`
- `lib/models/addon_info.dart`
- `lib/models/addon_repository.dart`
- `test/addon_models_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 2: AddonService local com persistência e isolamento ✅

**Description:** Implementar o contrato `AddonService`
(install/validate/enable/disable/update/uninstall/getCatalog/search/
resolvePlayback/getStatus) sobre armazenamento JSON local. Catálogo,
busca e resolução usam fixtures de demonstração; cada operação por
add-on é isolada (falha vira estado `erro` + diagnóstico, nunca
exceção para a UI). Instalação grava manifesto + origem + versão.

**Acceptance criteria:**
- [ ] Instalar manifesto válido persiste; inválido rejeita sem gravar
- [ ] Ativar add-on incompatível/plataforma divergente é recusado
- [ ] Add-on com defeito (catalog que lança) aparece em erro com
      diagnóstico; os demais continuam operando

**Verification:**
- [ ] Tests pass: `flutter test test/addon_service_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 1

**Files likely touched:**
- `lib/services/addon_service.dart`
- `lib/services/local_addon_service.dart`
- `test/addon_service_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 3: Tela Add-ons (lista, estados, detalhes, ativar/desativar/remover) ✅

**Description:** Nova rota `/addons` + entrada discreta no menu
principal. Lista de instalados com os 4 estados, tela de detalhes
(autor, versão, origem, permissões, aviso legal, última atualização),
ações ativar/desativar/remover com confirmação nas destrutivas, foco
visível e navegação por teclado. Dados de demonstração.

**Acceptance criteria:**
- [ ] Estados ativo/inativo/atualização/erro visíveis por add-on
- [ ] Remover pede confirmação e preserva mídias do usuário
- [ ] Tudo alcançável por teclado com foco visível

**Verification:**
- [ ] Tests pass: `flutter test test/addons_screen_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 2

**Files likely touched:**
- `lib/features/addons/addons_screen.dart`
- `lib/features/addons/addon_details_screen.dart`
- `lib/app/router.dart`, `lib/app/routes.dart`
- `test/addons_screen_test.dart`

**Estimated scope:** Medium: 3-5 files

## Checkpoint: Núcleo ✅ (74/74 testes, analyze limpo)

- [x] `flutter test` verde; `dart analyze` limpo
- [x] Instalar/ativar/desativar/remover funciona com add-on fictício
- [x] Falha de add-on vira estado de erro, sem derrubar o app

## Task 4: Fluxo de instalação (revisão de permissões, desativado por padrão) ✅

**Description:** Instalar por manifesto colado/arquivo/URL: validar,
exibir detalhes + permissões + aviso legal, permitir cancelar, e
instalar **desativado por padrão** quando a origem for nova/não
verificada. Ativação posterior valida permissões e compatibilidade.

**Acceptance criteria:**
- [ ] Permissões exibidas antes de confirmar; cancelar não grava nada
- [ ] Origem nova instala desativada; ativação checa compatibilidade
- [ ] Falha no meio desfaz a alteração (sem add-on pela metade)

**Verification:**
- [ ] Tests pass: `flutter test test/addon_install_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 3

**Files likely touched:**
- `lib/features/addons/addon_install_screen.dart`
- `lib/services/addon_fetcher.dart` (contrato + HTTP)
- `lib/services/addon_service.dart`, `lib/services/local_addon_service.dart`
- `lib/models/addon_manifest.dart` (`parseJson`)
- `test/addon_install_test.dart`, `test/addon_fetcher_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 5: Repositórios autorizados (cadastro, confiança, busca) ✅

**Description:** CRUD de repositórios (nome, origem, confiança) sobre
o `AddonFetcher` da Task 4 (fake para testes). Listar add-ons de um
repositório e instalar a partir dele.

**Acceptance criteria:**
- [ ] Adicionar/remover repositório com validação de endereço
- [ ] Repositório fora do ar mostra "fonte indisponível", sem travar
- [ ] Instalar item do repositório cai no fluxo da Task 4

**Verification:**
- [ ] Tests pass: `flutter test test/addon_repos_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 4

**Files likely touched:**
- `lib/services/local_addon_service.dart` (repositórios)
- `lib/features/addons/addon_repos_screen.dart`
- `test/addon_repos_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 6: Prova de isolamento fim a fim (add-on com defeito) ✅

**Description:** Fixture de add-on defeituoso (catálogo/busca/
reprodução lançam) exercitado pela UI: estado de erro com diagnóstico
e botões desativar/remover, tela inicial e player local seguem
utilizáveis, "fonte indisponível" em vez de tela travada.

**Acceptance criteria:**
- [ ] Add-on defeituoso não impede abrir o app nem o player local
- [ ] Diagnóstico legível + desativação imediata pela UI
- [ ] Nenhuma exceção do add-on chega à UI (tudo vira estado)

**Verification:**
- [ ] Tests pass: `flutter test test/addon_isolation_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 5

**Files likely touched:**
- `test/addon_isolation_test.dart`
- `lib/services/local_addon_service.dart` (ajustes)
- `lib/features/addons/addons_screen.dart` (ajustes)

**Estimated scope:** Small: 1-2 files

## Checkpoint: Instalação ✅ (126/126 testes, analyze limpo)

- [x] Instalar por manifesto/URL/repositório com validação e cancelamento
- [x] Origem nova instala desativada; ativação valida compatibilidade
- [x] Revisão humana antes de seguir para modo seguro

## Task 7: Contador de falhas + boot seguro + última alteração ✅

**Description:** Captura global de erros (`runZonedGuarded`,
`FlutterError.onError`) com registro persistente; contador de falhas
no arranque (zera após arranque limpo); a partir de 2 falhas,
inicializa em modo seguro (sem carregar add-ons) com faixa de aviso e
ação "desativar última alteração". Opção manual de modo seguro.

**Acceptance criteria:**
- [ ] 2 falhas simuladas no arranque ativam o modo seguro
- [ ] Modo seguro informa o motivo e oferece desativar o último
      componente alterado, sem perder biblioteca/histórico
- [ ] Arranque limpo zera o contador

**Verification:**
- [ ] Tests pass: `flutter test test/safe_mode_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 2

**Files likely touched:**
- `lib/services/startup_guard.dart` (novo)
- `lib/main.dart`
- `lib/features/home/home_screen.dart` (faixa)
- `test/safe_mode_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 8: Tela de diagnóstico e recuperação ✅

**Description:** Tela com versão, plataforma e estado dos componentes
(player, armazenamento, add-ons); ações separadas: restaurar padrões
(só prefs), limpar cache, limpar dados do app (com confirmação, sem
tocar mídias), exportar relatório sem dados sensíveis (área de
transferência), instruções de reinstalação por plataforma. Desativar
não é desinstalar.

**Acceptance criteria:**
- [ ] Restaurar padrões preserva biblioteca, histórico e vídeos
- [ ] Limpar dados pede confirmação e lista o que será apagado
- [ ] Relatório exportado contém versão/estados e nenhum caminho de
      mídia, URL ou credencial

**Verification:**
- [ ] Tests pass: `flutter test test/diagnostics_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 2

**Files likely touched:**
- `lib/features/diagnostics/diagnostics_screen.dart`
- `lib/services/diagnostics_service.dart`
- `lib/app/router.dart`, `lib/app/routes.dart`
- `test/diagnostics_test.dart`

**Estimated scope:** Medium: 3-5 files

## Checkpoint: Recuperação ✅ (156/156 testes, analyze limpo)

- [x] Falha repetida no arranque abre modo seguro sem add-ons
- [x] Restaurar padrões preserva biblioteca e histórico
- [x] Relatório de diagnóstico exportável sem dados sensíveis

## Task 9: Timeout, cancelamento, liberação e tipos de erro ✅

**Description:** Timeout de carga e de buffer com erro recuperável
(cancelar/tentar/voltar, sem reiniciar o app); liberar a sessão
anterior antes de abrir outra mídia; pré-checagem de arquivo local;
tipos de erro (rede/fonte/decodificador/desconhecido) com mensagens
distintas; log técnico local (etapa + duração, sem dados sensíveis).

**Acceptance criteria:**
- [ ] Fonte que não responde gera timeout com cancelar/tentar/voltar
- [ ] Erro informa se é rede, fonte ou decodificador quando dá para
      saber; nunca atribui ao player um erro do add-on/fonte
- [ ] Trocar de mídia libera a sessão anterior

**Verification:**
- [ ] Tests pass: `flutter test test/playback_recovery_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 2

**Files likely touched:**
- `lib/services/media_kit_player_service.dart`
- `lib/services/media_player_service.dart`
- `lib/models/playback_state.dart`
- `test/playback_recovery_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 10: Atualizações controladas (versões, changelog, adiar, compat, backup, rollback) ✅

**Description:** Detecção de atualização (versão do repositório >
instalada), tela mostrando versão atual/nova + changelog + plataforma,
ações atualizar/adiar por add-on, validação de compatibilidade antes
de ativar, backup das prefs antes de atualizar, rollback para o
manifesto anterior. Nada silencioso em componente crítico.

**Acceptance criteria:**
- [ ] Atualizar mostra antes/depois + changelog e pede confirmação
- [ ] Versão incompatível é bloqueada com motivo
- [ ] Adiar funciona; rollback restaura a versão anterior

**Verification:**
- [ ] Tests pass: `flutter test test/addon_updates_test.dart`
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 5

**Files likely touched:**
- `lib/features/addons/addon_updates_screen.dart`
- `lib/services/local_addon_service.dart`
- `test/addon_updates_test.dart`

**Estimated scope:** Medium: 3-5 files

## Task 11: Idiomas na exibição (sem português, proveniência) ✅

**Description:** No submenu de faixas, indicar quando o idioma
preferido não existe ("sem faixa em português"); na info do vídeo,
indicar a proveniência (arquivo local/add-on). Não traduzir títulos
automaticamente.

**Acceptance criteria:**
- [ ] Preferido ausente mostra aviso claro sem sair do player
- [ ] Proveniência exibida nas informações do vídeo
- [ ] Nenhum título traduzido automaticamente

**Verification:**
- [ ] Tests pass: `flutter test test/player_modes_test.dart` (estendido)
- [ ] Build succeeds: `dart analyze`

**Dependencies:** Task 2

**Files likely touched:**
- `lib/widgets/player_settings_panel.dart`
- `test/player_modes_test.dart`

**Estimated scope:** Small: 1-2 files

## Checkpoint: Completo ✅ (224/224 testes, analyze limpo)

- [x] Matriz de reprodução da spec exercitada nos testes
- [x] Critérios §22 (incluindo os 6 de add-ons) atendidos
- [x] Limitações registradas; pronto para revisão

## Fase 4: Preparação para TV

- [x] Task 12a: setas navegam com controles visíveis; seek só ocultos
- [x] Task 12b: foco visível + alcançabilidade auditados
- [x] Task 13: voltar hierárquico + foco preso em menus
- [x] Task 14: modo TV (controles maiores, 16:9, persistentes)
- [x] Task 15: boot em TV + checklist de validação em aparelho
- [x] Checkpoint: TV ✅ (252/252 testes, analyze limpo, APK debug com leanback)
- [x] Task 15b: pilotagem D-pad no AVD PlayerTV (71 dumps) —
      achados F1–F10 em `docs/VALIDACAO_TV.md`

## Fase 4b: Correções pós-validação em aparelho (F1–F10)

Comandos de verificação: `flutter test` + `dart analyze` +
pilotagem D-pad no AVD (ou TV física §24.8) antes de fechar.

- [x] F1: D-pad com controles ocultos (`select` + handler global) — provado no aparelho (seek/volume/OK)
- [x] F9: fonte local nunca diagnostica "rede" — provado no aparelho
- [x] F8-manifest: `READ_MEDIA_VIDEO` declarada + grant via adb toca `/sdcard` — runtime UX pendente
- [ ] F2: overlays de erro/concluído com foco alcançável
- [ ] F3: confirmação ao remover mídia (Cancelar focado)
- [ ] F4: saída D-pad do campo de texto
- [ ] F5: DOWN AppBar→controles (ou entrada garantida)
- [ ] F6: sem perda de foco à esquerda de Retroceder
- [ ] F7: Opções alcançável por direcional
- [ ] F8-runtime: pedir permissão de mídia em uso (UX + negado/rotas)
- [ ] F10: autofocus primário nas telas frias
- [ ] Checkpoint: revalidar F1–F10 no aparelho + suíte verde
