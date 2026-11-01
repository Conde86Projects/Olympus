# Release Checklist — v0.3.2

Versão publicada em 31/10/2026, `0.3.2+1008`.

- [x] `flutter analyze` limpo e 803 testes passando
- [x] versionName `0.3.2` na TCL e no emulador (`dumpsys`)
- [x] pacote do Windows abre pelo zip; versão `0.3.2+1008` no `player.exe`
- [x] logo na barra superior aprovada pelo dono
- [x] legenda boa aparece e fica marcada: TCL, Windows e emulador
- [x] legenda inválida mostra o aviso, mantém a anterior e o vídeo segue: TCL, Windows e emulador
- [x] vídeo sem legenda embutida com "Ativar por padrão" desligado: TCL e Windows
- [x] depois de repetir, a lista continua e o mesmo arquivo não duplica: TCL e Windows
- [x] vídeo com legenda embutida respeita a preferência: emulador

## Limites conhecidos

- Celular: o seletor do sistema pausa o vídeo; é preciso dar play ao voltar.
- Sem permissão de arquivos, o erro diz que o arquivo não está mais disponível no
  caminho salvo.
- TV: passar do último item do painel com a seta parece tirar o foco do painel.
- Duas legendas de pastas diferentes com o mesmo nome ficam iguais na lista.

## SHA-256

- `Olympus-0.3.2.apk`: `acfa3e741755fc16ca454909431a87b2f04e849f4fe28990762488c57ac77ddb`
- `Olympus-0.3.2-windows.zip`: `e23e5e22a9089190513b4d9d9c963e2fa526220b08e50692658740b8bf754d1d`
