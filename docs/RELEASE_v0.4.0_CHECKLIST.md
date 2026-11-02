# Release Checklist — v0.4.0

Versão publicada em 01/11/2026, `0.4.0+1012`. Spec #16 e #30.

## Automático

- [x] `flutter analyze` limpo e 1144 testes passando (01/11/2026)
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

- [x] subir `pubspec.yaml` e `appVersion`
- [x] mover o `[Não lançado]` do `CHANGELOG.md` para a versão
- [x] gerar o APK e o zip do Windows e registrar os SHA-256 aqui
- [x] pacote do Windows abre pelo zip; versão `0.4.0+1012` no `player.exe`
- [x] versionName `0.4.0` na TCL (`dumpsys`)
- [x] criar a tag e a release

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
- Pacote só funciona se trouxer `addon.json`; link de repositório do Kodi é recusado.
- Em Android 13 ou mais novo, o acesso de mídia do app pode não listar zip; nesse caso, use
  o link. A TCL (Android 9) lista normalmente.

## SHA-256

- `Olympus-0.4.0.apk`: `f6ffad1b433aff52f8708e339def24f95e9567f2741c81479a7a7b4401605e81`
- `Olympus-0.4.0-windows.zip`: `a003fc2da0e048669b0a1c502e7f41dda2f15089fdd6736045aa1992ebd196a5`
- `olympus-teste.zip`: `96915359e78fed5fd1a5c6b1430417c01f1510c495093a3c722191d7b17006ec`
