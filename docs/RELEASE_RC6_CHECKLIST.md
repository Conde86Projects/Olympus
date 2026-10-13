# Checklist de release — Olympus 0.1.0-rc.6

RC corretiva de consistência de versão (o diagnóstico exibia
`0.1.0-rc.1` fixo). Commit: `68fea9e` (só `pubspec.yaml` +
`AppConstants.appVersion`, mais a trava `version_consistency_test`).
Tag: `v0.1.0-rc.6` (anotada, em `68fea9e`). Sem tag final.
Tags anteriores intactas (`v0.1.0-rc.5` em `309255c`, etc.).

## Gates (antes da tag)

- [x] Suíte completa verde: 521/521 testes (`flutter test`).
- [x] `dart analyze` limpo, sem issues.
- [x] Árvore limpa no commit (só versionamento + trava).
- [x] `version_consistency_test`: `AppConstants.appVersion`
      acompanha o núcleo do `version:` do pubspec.

## Consistência das 4 fontes (confirmada na TCL)

- [x] `versionName=0.1.0-rc.6` via dumpsys após `adb install -r`.
- [x] `pubspec.yaml`: `0.1.0-rc.6+6`.
- [x] `AppConstants.appVersion`: `0.1.0-rc.6`.
- [x] Tela Diagnóstico e Sobre exibindo `0.1.0-rc.6`.

## Verificação curta na TCL (BeyondTV, Android 9, 1920x1080)

| Item | Resultado |
|---|---|
| Boot + Home | OK: biblioteca e histórico íntegros |
| Diagnóstico | OK: versão rc.6, erro antigo em texto puro, modo seguro "não" |
| Modo seguro manual | OK: banner após reinício, dados intactos; desligado e aparelho limpo |
| Exportação | OK: snackbar "sem caminhos, URLs ou credenciais" |
| Retomada HLS | OK: alvo 10:15 pousou exato, sem correção |
| Troca para 720p | OK: gate no 1º avanço, pouso em 111,2 s, sem correção nem rollback |
| Histórico | OK: ponto pós-troca (2:38) salvo corretamente |

## Limitações de validação (não são falhas confirmadas)

- Marcadores `[url]`/`[caminho]`/`[credencial]` na tela do
  aparelho: sem erro gravado com URL no período — valem os
  testes (7 de unidade + widget mostrando `falha em [url]`).
- Conteúdo do clipboard exportado: ilegível via dumpsys neste
  build — vale a varredura genérica em suíte (nenhum
  `scheme://`, caminho Windows ou segredo no relatório).
- Gatilho por falhas repetidas (contador de boots): a simulação
  com kill imediato não engata (morre antes do `beginBoot`) —
  vale o teste de limiar em suíte; o caminho manual foi
  exercido no aparelho.
- Retomada de item concluído mira o ponto final salvo
  (observado: alvo 634600/634634, pouso exato, overlay de
  conclusão): comportamento prévio de histórico, fora do
  escopo desta RC.

## Pendências separadas (não bloqueiam esta RC)

- Detecção fria de variantes HLS (não iniciada até fechar
  esta consistência).
- Modo seguro: gatilho por falha (acima) segue unitário.
- Diagnóstico: endurecimento contínuo.
