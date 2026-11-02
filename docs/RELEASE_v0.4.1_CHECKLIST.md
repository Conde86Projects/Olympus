# Release Checklist — v0.4.1

Versão publicada em 01/11/2026, `0.4.1+1013`. Só correções sobre a 0.4.0.

- [x] `flutter analyze` limpo e 1155 testes passando
- [x] `integration_test/addons_desktop_test.dart` no Windows real
- [x] zip de 2 GB descompactados: recusado em 30 ms, com 154 MB de memória (antes, 4133 MB)
- [x] gravação: falha no meio mantém o arquivo anterior; 40 gravações seguidas terminam
  na última
- [x] TCL: dados mantidos depois de fechar o app à força
- [x] TCL: filme parado em 0:18 continua dali pelo pôster da fileira
- [x] atualização para outro host de catálogo desativa e pede aprovação (teste automático)
- [x] versionName `0.4.1` na TCL (`dumpsys`)
- [x] pacote do Windows abre pelo zip; versão `0.4.1+1013` no `player.exe`

## Limites conhecidos

- Registro cortado por uma queda em versão anterior não é recuperado.
- A troca de host na atualização foi conferida só em teste automático.
- Queda real de energia no meio da gravação não foi provocada em aparelho.
- Os limites da v0.4.0 seguem valendo.

## SHA-256

- `Olympus-0.4.1.apk`: `dc28c3d1a065bd61222e199bd366d2f7d6ab7a6151fdcdde708ab5425cd01b19`
- `Olympus-0.4.1-windows.zip`: `84ceb1196cce0822c4cf67225b989c739a062bf216e37d0c5334d7d9afedf416`
