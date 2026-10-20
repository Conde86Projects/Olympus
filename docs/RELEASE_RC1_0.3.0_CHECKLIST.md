# Release Checklist — v0.3.0-rc.1

Candidata a release do ciclo 0.3.0 (política de volume por plataforma).
Base: commit `e2d932b` + bump de versão (sem tag criada).

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
  (97.823.968 bytes)
  - SHA-256:
    `2DBA6FF7BCD89606ED021D659B650DF82A4A8397DD726F2F3591A614367B5906`
- `build/windows/x64/runner/Olympus-0.3.0-rc.1-windows.zip`
  (pasta `Release` do `flutter build windows`)
  - SHA-256:
    `72F5592880339B330E3412AB6430B1ADE800F782C774A7DF24FD6405BB8D70A1`
- EXE avulso `player.exe` (93.184 bytes)
  - SHA-256:
    `729F342A2686339801C4E63B21E6E9F4B34F0561F7956631C40533C60E3D783E`

## Gates (20/10/2026)

- `flutter analyze`: limpo
- `dart analyze`: limpo
- `flutter test`: 671/671 verdes
- `flutter build windows`: OK
- `flutter build apk --release`: OK
- Segredos no diff: nenhum
- Tags `v0.2.0` (`9e2ad47`) e `v0.2.1` (`dbcbf93`): intactas —
  nenhuma tag nova criada

## Smoke test da RC1

### Celular

- [ ] versionName correto (Sobre: 0.3.0-rc.1)
- [ ] retrato
- [ ] paisagem
- [ ] botão físico de volume
- [ ] botão mudo (sem barra, sem +, sem −, sem gesto)
- [ ] catálogo definitivo (Fonte Própria, Big Buck Bunny)
- [ ] Big Buck Bunny
- [ ] play/pausa
- [ ] seek
- [ ] retomada
- [ ] tela cheia
- [ ] voltar
- [ ] histórico

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

### Windows

- [x] versionName correto (build `flutter build windows` OK)
- [x] abre e responde (PID 11080, `Responding: True`, deixado aberto
      para o teste interativo)
- [ ] trilho visual de volume
- [ ] mudo
- [ ] persistência
- [ ] janela normal
- [ ] janela pequena
- [ ] minimizar
- [ ] fechar pelo X
- [ ] catálogo
- [ ] reprodução
- [ ] retomada

## Critério para criar a tag `v0.3.0-rc.1`

Somente se: APK e Windows gerados; versões sincronizadas;
671+ testes verdes; analyze limpo; APK validado no celular e na
TCL; Windows validado; SHA-256 neste checklist; árvore limpa.
