# Checklist de release — Olympus 0.1.0-rc.7

RC da detecção fria de variantes HLS (investigação separada,
concluída e validada na TCL). Commit da feature: `25d59c1`;
marco: `09ca0af` (só `pubspec.yaml` + `AppConstants.appVersion`,
mais a trava `version_consistency_test`). Sem tag final. Tags
anteriores intactas (`v0.1.0-rc.6` em `68fea9e`, etc.).

## Gates (antes da tag)

- [x] Suíte completa verde: 530/521+9 testes (`flutter test`).
- [x] `dart analyze` limpo, sem issues.
- [x] Árvore limpa nos commits (feature + versionamento + checklist).
- [x] `version_consistency_test`: `AppConstants.appVersion`
      acompanha o núcleo do `version:` do pubspec.

## Consistência das 4 fontes (a confirmar na TCL no flash da RC7)

- [ ] `versionName=0.1.0-rc.7` via dumpsys após `adb install -r`.
- [x] `pubspec.yaml`: `0.1.0-rc.7+7`.
- [x] `AppConstants.appVersion`: `0.1.0-rc.7`.
- [ ] Tela Diagnóstico e Sobre exibindo `0.1.0-rc.7`.

## Validação da detecção fria na TCL (BeyondTV, Android 9, 14/10/2026)

Servidor HLS local no PC via `adb reverse` (determinístico, sem
derrubar o adb que passa pelo próprio Wi-Fi). Sonda limitada a
uma tentativa posterior de 3 s, só aquece a lista do seletor.

| Cenário | Resultado |
|---|---|
| Rede permanentemente indisponível | OK: abre o master de imediato com erro controlado; uma única `cold-failed attempt=1`; 20 s de silêncio depois; histórico zerado, ID e fonte intactos |
| Rede pronta (2x) | OK: abre direto a variante tetada 380p (`url_4`), toca (1:17/1:19 salvos), zero linhas `cold-*` |
| Rede fria com recuperação | OK: master aberto no timeout (`Opening x3.m3u8`, sem `url_4`); uma única `cold-ready attempt=1 count=5`; sem segundo open, sem seek, sem downgrade na janela; histórico zerado, ID e fonte intactos |

## Limitações de validação (não são falhas confirmadas)

- Prova de painel "Qualidade" aquecido pela sonda em background:
  no cenário frio o mpv estourou antes e o overlay de erro cobre
  o painel — vale o `count=5` no logcat + o teste de widget
  (seletor aparece após o aquecimento, sem reopen).
- Retomada HLS, seletor manual, política automática, modo seguro
  e diagnóstico: intocados (só adição; `fetchMasterText` não muda
  comportamento).
- Biblioteca do aparelho ganhou itens de teste (`cold-*`,
  fonte `127.0.0.1:8000`) e o `x36xhzz` segue em 2:38 — dados de
  validação, fora do git.
- Ordenação da Biblioteca com mesma fonte unifica pelo item
  existente (comportamento documentado do `upsert`): semear um
  item por URL.
