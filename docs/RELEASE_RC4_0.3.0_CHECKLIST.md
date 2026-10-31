# Release Checklist — v0.3.0-rc.4

Pré-release publicada em 31/10/2026, versão `0.3.0-rc.4+1005`. Substitui a rc.3.

## Mudanças desde a rc.3

- Retomada: o vídeo fica coberto até o ponto salvo, sem mostrar o início.
- Retomada sem internet: mostra erro com "Tentar novamente", em vez de ficar preso
  em "Ajustando a posição…".
- Código novo dividido em módulos, com testes próprios.

## Verificado

- [x] `flutter analyze` limpo e 778 testes passando
- [x] versionName `0.3.0-rc.4` na TCL e no emulador (`dumpsys`)
- [x] retomada sem mostrar o início (TCL, gravação da tela, em 0:26 e 2:41)
- [x] erro de conexão e nova tentativa ao voltar a rede (emulador)
- [x] sem internet, erro com opção de tentar de novo (Windows, dono, build anterior
      à troca de versão)
- [x] legenda com a barra visível (TCL, dono)

## Limites conhecidos

- "Tentar novamente" com a internet de volta: confirmado pelo dono na TCL e no Windows.
- Retomada em link leva alguns segundos a mais; em fonte que não anda, até 8 s.
- Fonte muito lenta pode cair no limite de 15 s do `network-timeout` ou de 30 s
  do início.
- 4K: clipe sintético de 30 s no PC do dono e na TCL, sem medir quadros perdidos.
- Modo TV ligado à mão em tela de celular: a engrenagem encosta no botão +10.

## SHA-256

- `Olympus-0.3.0-rc.4.apk`: `b2b1661db54fa754f26a68d574d3fd7d8d8130506860146dab08174a92ae517c`
- `Olympus-0.3.0-rc.4-windows.zip`: `c8b863728a9090a72d8e527215b8be13dd65617451487e8394c91514399e8082`
