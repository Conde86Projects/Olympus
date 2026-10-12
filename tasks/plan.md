# Implementation Plan: Add-ons, modo seguro e recuperação (spec v0.3)

## Overview

Aplicar as fases novas da especificação atualizada: gerenciador de
add-ons (Fase 5, com add-ons de demonstração — sem provedores reais),
modo seguro e recuperação (§26.2, §26.5), atualizações controladas
(§26.4, §26.11), isolamento de falhas (§26.14), endurecimento da
reprodução (timeout, cancelamento, liberação, diferenciação de erros —
§26.3, §26.10) e separação de idiomas na exibição (§26.12). Continua
fora: TV/Fase 4, integrações reais/Fase 6, miniaturas, qualidade
dinâmica, estilo de legenda (ver `docs/BACKLOG.md`).

## Architecture Decisions

- Add-ons do protótipo são **só manifesto + metadados** (sem código
  executável): a spec proíbe código arbitrário sem sandbox definido
  (§6.1) e manda demonstração antes de fontes reais (§23). Update e
  rollback operam sobre manifestos versionados.
- Falha de add-on **nunca propaga exceção para a UI**: o serviço
  captura por add-on e registra estado `erro` + diagnóstico (§26.14).
- Repositórios são buscados por um contrato `AddonRepoFetcher`
  injetável (implementação real via HTTP + fake para testes), para a
  suíte não depender de rede.
- Modo seguro é conservador: contador persistente de falhas no
  arranque + captura global (`runZonedGuarded`, `FlutterError`) +
  opção manual sempre disponível no diagnóstico.
- Timeout de carga/buffer e classificação de erro (rede/fonte/
  decodificador/desconhecido) vivem na camada do player atrás do
  contrato existente; telas não importam o media_kit.

## Task List

### Phase A: Núcleo de add-ons

- [x] Task 1: Modelos de add-on + validação de manifesto
- [x] Task 2: AddonService local com persistência e isolamento
- [x] Task 3: Tela Add-ons (lista, estados, detalhes, ativar/desativar/remover)
- [ ] Task 2: AddonService local com persistência e isolamento
- [ ] Task 3: Tela Add-ons (lista, estados, detalhes, ativar/desativar/remover)

### Checkpoint: Núcleo ✅ (74/74 testes, analyze limpo)

- [x] `flutter test` verde; `dart analyze` limpo
- [x] Instalar/ativar/desativar/remover funciona com add-on fictício
- [x] Falha de add-on vira estado de erro, sem derrubar o app

### Phase B: Instalação e repositórios

- [ ] Task 4: Fluxo de instalação (revisão de permissões, desativado por padrão)
- [ ] Task 5: Repositórios autorizados (cadastro, confiança, busca)
- [ ] Task 6: Prova de isolamento fim a fim (add-on com defeito)

### Checkpoint: Instalação

- [ ] Instalar por manifesto/URL/repositório com validação e cancelamento
- [ ] Origem nova instala desativada; ativação valida compatibilidade
- [ ] Revisão humana antes de seguir para modo seguro

### Phase C: Modo seguro e recuperação

- [ ] Task 7: Contador de falhas + boot seguro + última alteração
- [ ] Task 8: Tela de diagnóstico e recuperação

### Checkpoint: Recuperação

- [ ] Falha repetida no arranque abre modo seguro sem add-ons
- [ ] Restaurar padrões preserva biblioteca e histórico
- [ ] Relatório de diagnóstico exportável sem dados sensíveis

### Phase D: Endurecimento e atualizações

- [x] Task 9: Timeout, cancelamento, liberação e tipos de erro
- [x] Task 10: Atualizações controladas (versões, changelog, adiar, compat, backup, rollback)
- [x] Task 11: Idiomas na exibição (sem português, proveniência)

### Checkpoint: Completo ✅ (224/224 testes, analyze limpo)

- [x] Matriz de reprodução da spec exercitada nos testes
- [x] Critérios §22 (incluindo os 6 de add-ons) atendidos
- [x] Limitações registradas; pronto para revisão

### Phase E: Preparação para TV (Fase 4 da spec)

- [x] Task 12: Setas + foco (§18, §12.2) — traversal direcional vs.
      seek/volume; foco visível em todos os interativos
- [x] Task 13: Voltar hierárquico + foco preso em menus (§18, §12.2)
- [x] Task 14: Modo TV (§3.4, §12.2) — controles maiores, layout
      16:9, controles persistentes navegando
- [x] Task 15: Boot em TV + validação em aparelho (manifest leanback,
      paisagem, checklist Android TV/Tizen; §24.8)

### Checkpoint: TV ✅ (252/252 testes, analyze limpo, APK debug com leanback)

- [x] Só setas + OK + voltar operam o app inteiro
- [x] Foco sempre visível, ordem segue o visual
- [x] Checklist de validação em aparelho entregue

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Strings de erro do media_kit frágeis para classificar falha | Med | Pré-checagem de arquivo local + timeouts próprios; `desconhecido` como fallback honesto |
| Detecção de falha no arranque pouco confiável no desktop | Med | Contador conservador + modo seguro manual sempre acessível |
| Escopo escorregar para Fase 6 (provedores reais) | High | Add-ons manifesto-somente; sem execução de código; sem credenciais |
| Formato de pacote/assinatura ainda pendentes na spec | Low | Validar manifesto JSON + checksum opcional; assinatura documentada como futura |

## Open Questions

- Formato final do pacote de add-on (§24.10): protótipo usa manifesto
  JSON — confirmado?
- Política de assinatura (§24.11): checksum opcional agora, assinatura
  depois — confirmado?
- Nível de log técnico local aceitável (o que pode ser persistido)?

## Parallelization Opportunities

- Tasks 1→2→3 são sequenciais (contrato antes da UI).
- Tasks 7 e 8 podem andar juntas após a 2 (leem o mesmo serviço).
- Tasks 9, 10, 11 são independentes entre si após a 2.
- Testes de widget de tarefas prontas podem ser escritos em paralelo.
