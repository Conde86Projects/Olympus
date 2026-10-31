# Release Checklist — v0.3.0-rc.2

Pré-release publicada em 31/10/2026. Tag no commit `a025130`, versão
`0.3.0-rc.2+1003`.

## Artefatos publicados

- `Olympus-0.3.0-rc.2.apk`
  - SHA-256: `78274D2D72B78BF65198915268294F8A29A1ECD82C8C543D7DDE475C5DE3F385`
- `Olympus-0.3.0-rc.2-windows.zip`
  - SHA-256: `0D579D516D5BA37B5B0F86C872765D6EB7B49A7D494892F2746E04AAC9D82669`

## Verificado nesta versão

- [x] `flutter analyze` limpo e 753 testes passando
- [x] versionName `0.3.0-rc.2` na TCL e no emulador (`dumpsys`)
- [x] foco visível em Ajustes e no painel do player (TCL)
- [x] legenda desenhada pelo app, acima da base (TCL, emulador)
- [x] legenda no Windows (dono, no build anterior à troca de versão)
- [x] tela cheia e paisagem (emulador, `ROTATION_90`)

## Corrigido depois da rc.2 (fora dos artefatos publicados)

- `5be75a8`: legenda acima da barra de controles; tamanho, cor, posição e fundo
  em Ajustes. Verificado no emulador; navegação das opções na TCL.
- `00b8dca`: queda de rede antes do primeiro quadro deixava tela preta sem erro;
  queda no meio do vídeo culpava o dispositivo. Mensagem verificada no emulador;
  o vigia da tela preta está coberto por teste automatizado.
- `3a80efb`: seletor de qualidade aparece quando o master volta depois de
  10 s (U11). Verificado no emulador com servidor local.

## Limites conhecidos

- Queda de rede testada só no emulador. Fonte muito lenta pode cair no limite de
  15 s do `network-timeout` ou de 30 s do início.
- 4K: clipe sintético H.264 de 30 s tocou no PC do dono e avançou na TCL, sem
  medir quadros perdidos. Outros aparelhos não foram testados.
- Windows ainda não testado com os commits acima.
- Modo TV ligado à mão em tela de celular: a engrenagem encosta no botão +10.
