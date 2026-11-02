# Release Checklist — v0.4.0

Ainda não publicada. O número 0.4.0 é a proposta para esta entrega; `pubspec.yaml` e
`appVersion` seguem em `0.3.5` até a publicação. Branch `integracao/addons-zip`, spec
#30. Sem tag.

## Automático

- [x] `flutter analyze` limpo e 1132 testes passando (01/11/2026)

## TV TCL (controle pelo adb, 01/11/2026)

- [x] Início com fileiras e foco no primeiro cartão
- [x] setas entre cartões e fileiras, com o título do cartão visível ao descer
- [x] seta para baixo chega às opções do cartão, e o menu abre com OK
- [x] voltar do item aberto mantém o foco no mesmo cartão
- [x] primeiro voltar leva a "Abrir arquivo"; o segundo sai do app
- [x] arquivo ausente abre a tela de erro e, ao voltar, fica fora de "Continuar assistindo"
- [ ] vídeo tocando a partir do Início (o item testado tinha o arquivo ausente e caiu
  na tela de erro)
- [ ] fileira de add-on real
- [ ] zip por link e pelo caminho digitado
- [ ] seletor de arquivos em "Neste aparelho": abre, ou o app orienta a usar caminho
  ou link

## Celular (emulador, 360 dp, 01/11/2026)

- [x] fileiras dentro das abas; nome da fonte em linha própria
- [x] abrir um vídeo e voltar ao Início
- [x] sair logo depois de abrir mantém a posição salva
- [x] "Instalar de zip" bloqueado, com motivo e atalho; aviso com foco em Cancelar
- [x] fonte de teste por link: revisão, aceite e instalação desativada
- [x] ativar e ver a fileira no Início, com pôster 2:3
- [x] tocar o pôster abre e reproduz o vídeo
- [ ] instalar zip pelo seletor de arquivos
- [ ] celular físico

## Windows

- [x] Início abre com as fileiras e as miniaturas reais (só imagem da janela, sem
  clique)
- [ ] instalação limpa: instalar zip bloqueado, com motivo e atalho
- [ ] instalar um zip válido: revisão completa e entrada desativada
- [ ] ativar e tocar um item, que aparece em "Continuar assistindo"
- [ ] zip do Kodi, zip com `.py` e zip cortado: três mensagens diferentes, nada instalado
- [ ] desligar fontes desconhecidas: o add-on segue ativo e instalar outro é bloqueado
- [ ] remover o add-on: a pasta some e as mídias locais ficam
- [ ] tela cheia no monitor de 34": largura total, sem cartão gigante, setas funcionando
- [ ] derrubar a rede com um add-on ativo: só a fileira dele mostra erro
- [ ] mouse: passar por cima, clique direito e menu do cartão

## Publicação (só com ordem do dono)

- [ ] subir `pubspec.yaml` e `appVersion`
- [ ] mover o `[Não lançado]` do `CHANGELOG.md` para a versão
- [ ] gerar o APK e o zip do Windows e registrar os SHA-256 aqui
- [ ] criar a tag e a release

## Limites conhecidos

- Add-on do Kodi em Python não funciona: o pacote do Olympus só traz dados (ADR-0004).
- O cartão 2:3 de catálogo corta ao centro as imagens horizontais.
- Catálogo vazio some da tela principal e só volta ao reabrir o app ou se o add-on mudar.
- Na TV, o menu do cartão abre sem item destacado; o destaque vem na primeira seta.
- Registro antigo de vídeo que falhou continua em "Continuar assistindo" até ser removido
  pelo menu do cartão; a correção vale para as próximas aberturas.
- Sem assinatura de pacote: zip por arquivo ou link mostra o SHA-256 para conferir, e só
  repositório compara com um valor publicado.
- Linux e macOS não foram testados.
