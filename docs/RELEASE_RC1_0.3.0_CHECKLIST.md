# Release Checklist — v0.3.0-rc.1

Candidata a release do ciclo 0.3.0 (política de volume por plataforma).
Base: commit `a2e8bb2` (tag `v0.3.0-rc.1` criada 24/10/2026). RC1
preparada em `4d2d4fb` (20/10/2026, sem tag).

## Versões (sincronizadas)

- `pubspec.yaml`: `0.3.0-rc.1+1`
- `AppConstants.appVersion`: `0.3.0-rc.1`
- Diagnóstico: deriva de `AppConstants` ✓ (travado em
  `test/version_consistency_test.dart`)
- Tela Sobre: deriva de `AppConstants` ✓
- APK `versionName`: `0.3.0-rc.1` (`versionCode 1`, do pubspec) ✓
  (confirmado via `dumpsys package` no celular e na TCL)

## Artefatos

- `build/app/outputs/flutter-apk/app-release.apk`
  (97.823.968 bytes, build da RC1 em `4d2d4fb`)
  - SHA-256:
    `2DBA6FF7BCD89606ED021D659B650DF82A4A8397DD726F2F3591A614367B5906`
- APK validado nos aparelhos (pós-lote do mudo, 21/10/2026;
  binário idêntico ao rebuild do HEAD — só docs/testes mudaram depois)
  - SHA-256:
    `D06A92572E99FC2F2B838C6AC23FE7C58690C216D87DC6C592601CF93EBCC751`
- `build/windows/x64/runner/Olympus-0.3.0-rc.1-windows.zip`
  (rebuild do HEAD em 24/10/2026; `data/` com o lote do mudo)
  - SHA-256:
    `75DDBF77B2017F5A0615046A7978F3D5BB71B1851815C6C4CAB88FC36A0148C9`
- EXE avulso `player.exe` (93.184 bytes, stub inalterado desde 20/10 —
  o código Dart vai em `data/`)
  - SHA-256:
    `729F342A2686339801C4E63B21E6E9F4B34F0561F7956631C40533C60E3D783E`

## Gates (20/10/2026; revistos 24/10/2026)

- `flutter analyze`: limpo
- `dart analyze`: limpo
- `flutter test`: 677/677 verdes (era 671/671 em 20/10)
- `flutter build windows`: OK (rebuild do HEAD em 24/10)
- `flutter build apk --release`: OK
- Segredos no diff: nenhum
- Tags `v0.2.0` (`9e2ad47`) e `v0.2.1` (`dbcbf93`): intactas —
  tag nova `v0.3.0-rc.1` (`d7a80fd`, anotada, push feito 24/10)

## Smoke test da RC1

### Celular

- [x] versionName correto (Sobre: 0.3.0-rc.1, `dumpsys`, 24/10)
- [ ] retrato
- [ ] paisagem
- [x] botão físico de volume (despluga o mudo, 24/10)
- [x] botão mudo (sem barra, sem +, sem −, sem gesto)
- [x] catálogo definitivo (Fonte Própria, Big Buck Bunny)
- [x] Big Buck Bunny (HLS multivariante publicado, 24/10)
- [x] play/pausa
- [x] seek
- [x] retomada
- [ ] tela cheia
- [x] voltar
- [x] histórico
- [x] Qualidade: Automática · efetiva no painel (dono, 24/10)
- [x] manual 360p e volta à Automática (dono, 24/10)
- [x] rede fria: abre e lista Qualidade (dono, 24/10)

### TCL

- [ ] versionName correto (0.3.0-rc.1)
- [x] VOL+ aumenta volume do sistema (3 → 5)
- [x] VOL− diminui volume do sistema
- [x] mudo do aplicativo funciona (volume_off)
- [x] D-pad não altera volume (sistema ficou em 5,
      `initialVolume` ficou em 1.0, barra só reexibiu)
- [x] catálogo (Fonte Própria, Big Buck Bunny 9:56)
- [x] reprodução (frames de vídeo confirmados)
- [x] seek (lateral +10 s, progresso 1:53 → ~2:03)
- [x] retomada (cartão "parou em 1:53", abriu retomando)
- [x] histórico (cartão Continuar assistindo com progresso 19%)
- [x] retorno ao catálogo (BACK encadeado até a home)
- [x] Qualidade no BBB HLS vs master publicado (dono, 24/10)

### Windows

- [x] versionName correto (rebuild do HEAD em 24/10: OK)
- [x] abre e responde (PID 24208, deixado aberto para o re-check)
- [x] Qualidade no BBB HLS (Automática · efetiva, dono, 24/10)
- [x] manual 360p e volta à Automática (dono, 24/10)
- [x] rede fria: abre e lista Qualidade (dono, 24/10)
- [x] fileira só com mudo, sem trilho (novo build, dono, 24/10)
- [x] setas ocultas com persistência (dono, 24/10)
- [ ] janela normal
- [ ] janela pequena
- [ ] minimizar
- [ ] fechar pelo X
- [ ] mudo
- [ ] persistência
- [ ] catálogo
- [ ] reprodução
- [ ] retomada

## Critério para criar a tag `v0.3.0-rc.1`

Somente se: APK e Windows gerados; versões sincronizadas;
671+ testes verdes; analyze limpo; APK validado no celular e na
TCL; Windows validado; SHA-256 neste checklist; árvore limpa.
