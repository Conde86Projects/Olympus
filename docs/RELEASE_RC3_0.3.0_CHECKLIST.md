# Release Checklist — v0.3.0-rc.3

Pré-release publicada em 31/10/2026, versão `0.3.0-rc.3+1004`. Substitui a rc.2.

## Mudanças desde a rc.2

- Legenda sobe acima da barra de controles quando ela está visível.
- Ajustes: tamanho, cor, posição e fundo da legenda.
- Queda de rede antes do primeiro quadro vira erro com "Tentar novamente", em
  vez de tela preta sem aviso.
- Queda de rede no meio do vídeo mostra mensagem de conexão, sem culpar o
  dispositivo.
- Seletor de qualidade aparece quando o master volta depois de 10 s (U11).

## Verificado

- [x] `flutter analyze` limpo e 762 testes passando
- [x] versionName `0.3.0-rc.3` na TCL e no emulador (`dumpsys`)
- [x] legenda, cor e posição acima da barra (emulador)
- [x] legenda e Ajustes no Windows (dono, no build anterior à troca de versão)
- [x] opções de legenda alcançáveis e alteráveis com o controle (TCL)
- [x] queda de rede no meio do vídeo e nova tentativa (emulador)
- [x] U11 com servidor local (emulador)

## Limites conhecidos

- Tela preta antes do primeiro quadro: correção coberta por teste automatizado;
  no aparelho, o novo teste terminou em erro de conexão, possivelmente pela
  abertura, e não reproduziu exatamente o travamento.
- Queda de rede não testada na TCL nem no Windows.
- Fonte muito lenta pode cair no limite de 15 s do `network-timeout` ou de 30 s
  do início.
- Legenda com a barra visível não conferida na TCL.
- 4K: clipe sintético H.264 de 30 s tocou no PC do dono e avançou na TCL, sem
  medir quadros perdidos. Outros aparelhos não foram testados.
- Modo TV ligado à mão em tela de celular: a engrenagem encosta no botão +10.

## Artefatos

- `Olympus-0.3.0-rc.3.apk`
  - SHA-256: `cea86010f6d9e9c75979b1f484cb56f27223df50d8b1e0097dc0854c9d132b35`
- `Olympus-0.3.0-rc.3-windows.zip`
  - SHA-256: `badb92b3203120f282fa204b71c80a916cfc58b68993dc93b8241380b4212208`

## Teste de queda na TCL (depois da publicação)

Fonte derrubada por `adb reverse`, sem cortar o Wi-Fi da TV.

- Queda durante a reprodução: erro com "Tentar novamente" apareceu, mas o tempo
  até o erro não foi medido. O mpv pulou os segmentos que faltavam e, quando a
  fonte voltou, seguiu sozinho atrás da tela de erro, adiantado no vídeo.
- Abertura com posição salva e fonte fora do ar: **a interface congela** em
  "Ajustando a posição…" e não responde ao controle. Voltou só com a fonte de
  volta. Causa não encontrada; pode ser efeito do `adb reverse`.
- `Tentar novamente` não confirmado na TCL.
- Prazo de 5 s no seek da retomada (commit local) cobre o caso em teste, mas não
  resolveu esse congelamento.
