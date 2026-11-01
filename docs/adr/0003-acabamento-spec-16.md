# Acabamento da spec #16

Status: accepted.

O ciclo da spec #16 (tickets #17 a #27) fecha o que a Especificação promete e os limites deixados pelas versões 0.3.2 a 0.3.5. Esta nota registra as decisões que a próxima pessoa não consegue ler só no código. O ciclo está no PR #29 e ainda não foi publicado.

## Decisões assentadas

- Tamanho do texto vale para o app inteiro, aplicado uma vez na raiz antes do teto da classe de largura da TV, que continua valendo para o layout da TV nunca quebrar. Fica em três degraus (Normal 1,0, Grande 1,15, Maior 1,3). A legenda desenhada pelo app fica de fora: tem ajuste próprio.
- Erro de arquivo sem acesso vira permissão por consulta ao acesso. No Android recente, sem permissão de mídia o arquivo parece ausente ou o motor diz só "falhou ao abrir" (parece rede), sem falar em permissão. Em arquivo local o app consulta se tem acesso aos arquivos: sem acesso, o erro é de permissão; com acesso, segue o tipo que veio. Isso evita depender do texto do motor, que não é contrato estável. Link nunca mostra a mensagem de permissão.
- Atalhos: fixos para a navegação básica (espaço, Enter, Esc, setas, Tab), configuráveis para as sete ações do player (Mudo, Tela cheia, Informações, Legendas, Áudio, Modo cinema, Fechar player). A tela de atalhos recusa tecla reservada e tecla já usada por outra ação, dizendo o motivo. Valor salvo inválido ou em conflito cai no padrão (M, F, I, S, A, C, Q). Os atalhos não disparam com campo de texto em foco.
- Início e Configurações nunca saem do menu principal. Só Biblioteca, Favoritos, Add-ons e Histórico podem ser escondidos, para o usuário nunca ficar sem acesso às configurações. Esconder não desliga add-ons instalados. No celular a aba ativa é guardada por destino, não por posição, para esconder uma aba não trocar a tela do usuário.
- Legenda ao lado no celular só avisa. O Android recente só libera ao app arquivos de mídia, e `.vtt` e `.ass` não contam. O app não pede "acesso a todos os arquivos". Em vídeo local sem legenda achada, o painel de legendas avisa que ela pode ser aberta à mão por "Abrir arquivo de legenda…".
- Miniatura no Windows pelo motor do app (v0.3.5): o próprio motor de reprodução tira o quadro, sem precisar instalar nada.
- Informações técnicas do erro nunca mostram caminho de pastas, endereço completo nem credencial: arquivo mostra só o nome, link mostra só o servidor, e a mensagem do motor passa pelo mesmo limpador do diagnóstico.
- Fim do vídeo com Biblioteca e Início fecha o player pelo mesmo caminho do "Fechar" (salva a sessão) e só depois navega.
- Painel de opções na TV é um escopo de foco próprio: as setas não saem dele. Fora da TV segue o escopo do diálogo, como antes.
- Celular: o app lembra se o vídeo estava tocando antes de ir a segundo plano (seletor do sistema) e só retoma o play se estava; vídeo pausado fica pausado.
- Legendas com o mesmo nome em pastas diferentes mostram `pasta/nome` na lista; a faixa marcada é decidida pelo caminho completo do arquivo.

## Considered Options

- Pedir "acesso a todos os arquivos" no Android para a legenda ao lado funcionar. Rejeitado: permissão ampla demais para um player, fora do escopo da spec.
- Deixar todas as teclas configuráveis. Rejeitado: sem espaço, Enter, Esc, setas e Tab fixos, uma troca ruim deixa o app sem navegação.
- Deixar o usuário esconder Início e Configurações. Rejeitado: sem Configurações não há como desfazer.

## Consequences

A configuração padrão não muda nada para quem não mexer em nada. Preferências novas (`textSize`, `hiddenDestinations`, `shortcuts`) caem no padrão quando o valor salvo é desconhecido. Foram conferidos em aparelho em 01/11/2026: na TCL, a data do cartão, o fim do vídeo, o menu principal e o foco do painel; no emulador, o texto maior, o erro de permissão, as informações técnicas e o aviso de legenda ao lado. Fica para o checklist da versão que publicar o ciclo: atalhos e texto maior no Windows, e as legendas de mesmo nome em pastas diferentes.

## Em aberto

Idioma da interface, fontes reais, assinatura de pacotes e "Abrir com" ficam fora deste ciclo.
