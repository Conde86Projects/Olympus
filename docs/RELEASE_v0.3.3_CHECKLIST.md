# Release Checklist — v0.3.3

Versão publicada em 31/10/2026, `0.3.3+1009`.

- [x] `flutter analyze` limpo e 809 testes passando
- [x] versionName `0.3.3` na TCL e no emulador (`dumpsys`)
- [x] pacote do Windows abre pelo zip; versão `0.3.3+1009` no `player.exe`
- [x] `.vtt` e `.ass` escolhidos no seletor do sistema e com texto na tela: emulador
- [x] arquivo que não é legenda mostra o aviso: teste automático
- [x] painel marca a faixa ligada e desligar funciona, com "Ativar por padrão": emulador e Windows
- [x] legenda ao lado `.srt`: emulador e Windows
- [x] legenda ao lado `.vtt` e `.ass`: TCL e Windows
- [x] legenda ao lado inválida não atrapalha o vídeo: emulador e Windows
- [x] sem legenda ao lado, nada muda: emulador
- [x] "Ativar por padrão" desligado mantém a legenda ao lado desligada: TCL, emulador e Windows

## Limites conhecidos

- Celular: escolhendo o vídeo pelo seletor do sistema, a legenda ao lado não é
  encontrada, porque o app recebe uma cópia do vídeo. Abra a legenda pelo painel.
- Emulador com Android recente: `.vtt` e `.ass` ao lado do vídeo não foram
  encontrados nem com o caminho digitado. A causa provável é o acesso a arquivos do
  Android, mas não foi confirmada.
- Celular: o seletor do sistema pausa o vídeo; é preciso dar play ao voltar.
- Sem permissão de arquivos, o erro diz que o arquivo não está mais disponível no
  caminho salvo.
- TV: passar do último item do painel com a seta parece tirar o foco do painel.
- Duas legendas de pastas diferentes com o mesmo nome ficam iguais na lista.

## SHA-256

- `Olympus-0.3.3.apk`: `37f06658e1c02245647058b6f7a94c5b2de8e3cdc81c899b57644e0d6c3825fa`
- `Olympus-0.3.3-windows.zip`: `a4e506d35b229012faba297229811aa494b94ba2027614e1a39a28438ea63506`
