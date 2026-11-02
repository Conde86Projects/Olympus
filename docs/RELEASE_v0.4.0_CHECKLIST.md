# Release Checklist — v0.4.0

Ainda não publicada. O número 0.4.0 é a proposta para esta entrega; `pubspec.yaml` e
`appVersion` seguem em `0.3.5` até a publicação. Branch `integracao/addons-zip`, spec
#30. Sem tag.

## Automático

- [x] `flutter analyze` limpo e COUNT testes passando (01/11/2026)
- [x] `integration_test/addons_desktop_test.dart` no Windows real, com disco, rede e
  motor de vídeo de verdade, em pastas temporárias

## TV TCL (controle pelo adb, 01/11/2026)

- [x] Início com fileiras e foco no primeiro cartão
- [x] setas entre cartões e fileiras, com o título do cartão visível ao descer
- [x] seta para baixo chega às opções do cartão, e o menu abre com OK
- [x] voltar do item aberto mantém o foco no mesmo cartão
- [x] primeiro voltar leva a "Abrir arquivo"; o segundo sai do app
- [x] arquivo ausente abre a tela de erro e, ao voltar, fica fora de "Continuar assistindo"
- [x] vídeo tocando a partir do Início, retomando do ponto salvo
- [x] balão só nos ícones da barra do topo; nada nas opções do cartão
- [x] instalar de zip bloqueado, ativar fontes e entrar na aba Zip com foco em "Procurar"
- [x] "Procurar pacote…" abre o navegador próprio da TV; `olympus-teste.zip` revisa,
  instala desativado e ativa
- [x] fileira de add-on real, com pôster, e o filme toca pelo pôster
- [ ] caminho digitado e link na TV: o teclado da TV não aceita texto pelo adb. Mesmo
  código do Windows e do emulador, onde passaram

## Celular (emulador, 360 dp, 01/11/2026)

- [x] fileiras dentro das abas; nome da fonte em linha própria
- [x] abrir um vídeo e voltar ao Início
- [x] sair logo depois de abrir mantém a posição salva
- [x] "Instalar de zip" bloqueado, com motivo e atalho; aviso com foco em Cancelar
- [x] fonte de teste por link: revisão, aceite e instalação desativada
- [x] ativar e ver a fileira no Início, com pôster 2:3
- [x] tocar o pôster abre e reproduz o vídeo
- [x] zip por link público real: baixa, segue redirecionamento e recusa o que não é pacote
- [ ] instalar zip pelo seletor de arquivos
- [ ] celular físico

## Windows (teste de integração, 01/11/2026)

- [x] instalação limpa: instalar zip bloqueado, com motivo e atalho
- [x] zip do Kodi, zip com `.py` e zip cortado: três mensagens diferentes, nada instalado
- [x] zip válido pelo caminho digitado: revisão com SHA-256 e entrada desativada
- [x] zip válido por link (servidor local): baixa, revisa e instala
- [x] ativar: a fileira aparece e o filme toca pelo pôster, com o motor real
- [x] o vídeo tocado aparece em "Continuar assistindo"
- [x] desligar fontes desconhecidas: o add-on segue ativo e instalar outro é bloqueado
- [x] remover o add-on: a pasta some e as mídias locais ficam
- [x] mouse: balão na barra do topo, invisível no cartão e no player; clique direito
  abre o menu do cartão
- [x] Início abre com as fileiras e as miniaturas reais
- [ ] seletor de arquivos do Windows em "Procurar pacote…" (janela do sistema)
- [ ] tela cheia no monitor de 34": conferido só em simulação de 3440 x 1440
- [ ] derrubar a rede com um add-on ativo: coberto por teste automático, sem conferir
  no aparelho

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
