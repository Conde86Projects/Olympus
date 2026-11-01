# Release Checklist — v0.3.5

Versão publicada em 01/11/2026, `0.3.5+1011`.

- [x] `flutter analyze` limpo e 850 testes passando
- [x] versionName `0.3.5` na TCL e no emulador (`dumpsys`)
- [x] pacote do Windows abre pelo zip; versão `0.3.5+1011` no `player.exe`
- [x] teste de integração no Windows real (`integration_test/thumbnail_test.dart`):
  mp4, mkv, webm, avi, clipe de 1 s e 4K geram miniatura de 320 px com cerca de 9 KB;
  só áudio, arquivo cortado e arquivo de texto ficam sem miniatura; quatro pedidos
  juntos saem em fila
- [x] app real no Windows: mp4, mkv, webm e 4K ganharam miniatura; o arquivo cortado
  ficou com o ícone de play; o 4K aparece na Biblioteca, mas não em "Continuar
  assistindo" por estar concluído
- [x] Android sem regressão: vídeo novo ganha miniatura pelo caminho nativo (emulador)

## Limites conhecidos

- A miniatura é gerada depois de abrir o vídeo, com cerca de 2 a 3 s de atraso (1,5 s
  de espera para a tela abrir primeiro, mais o tempo de decodificar).
- Arquivo que o motor não abre gasta até 5 s em segundo plano a cada vez que é aberto
  e fica no ícone de play.
- Só vídeos locais; links seguem no ícone de play.
- Linux e macOS usam o mesmo caminho do Windows, mas não foram testados.
- Os limites da v0.3.4 seguem valendo.

## SHA-256

- `Olympus-0.3.5.apk`: `d4a7ceb283bae1d47c9101db50951f8e9129dc05feeb8460ff6e9ffc2caaf290`
- `Olympus-0.3.5-windows.zip`: `f73318ba2649aaf493d2491882a84846a5fdbd69ffa845d36a10eecd15e8301a`
