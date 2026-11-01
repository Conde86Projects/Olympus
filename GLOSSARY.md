# Olympus

Player de mídia do dono: catálogo próprio, reprodução HLS e controle simples de volume no celular, na TV e no Windows.

## Language

**Mudo do app**:
Estado interno que zera o áudio do player sem tocar no volume do aparelho.
_Avoid_: mute, silencioso

**Mudo do sistema**:
Aparelho zerado ou com mudo ativado, fora do controle do app.
_Avoid_: silêncio do sistema, mudo da TV

**Desplugar o mudo**:
Sair do mudo do app automaticamente quando o volume do sistema sobe.

**Mutar com o sistema**:
Entrar no mudo do app automaticamente quando o volume do sistema zera (ou o mudo do aparelho é ativado). Vale na TV e no celular; a abertura do player não muta sozinha.
_Avoid_: desmutar, unmute

**Trilho**:
Controle deslizante de volume interno, removido de todas as plataformas; no player resta só o mudo.
_Avoid_: slider, barra de volume

**Setas ocultas**:
Ajuste fino de volume no desktop com a barra escondida; o valor vira o volume inicial.
_Avoid_: atalho de volume, teclas de volume

**Volume inicial**:
Preferência de volume aplicada ao abrir o player; persistida só no desktop.
_Avoid_: volume padrão, volume salvo

**Chrome mobile**:
O que o aparelho mostra e esconde em volta do vídeo no celular: imersão, orientação, visibilidade dos controles e gestos de toque. Vive num módulo único com estado próprio.
_Avoid_: UI do player, barra do celular

**Tamanho do texto**:
Ajuste em Configurações > Aparência (Normal, Grande, Maior) que multiplica o texto do sistema por 1,0, 1,15 ou 1,3 no app inteiro. Não muda a legenda desenhada pelo app, que tem ajuste próprio em Legendas.
_Avoid_: zoom, fonte, escala da tela

**Menu principal**:
Os destinos de navegação sempre à mão: a barra inferior no celular e a barra superior no computador e na TV. Biblioteca, Favoritos, Add-ons e Histórico podem ser escondidos; Início e Configurações nunca saem. Esconder um destino não desliga nem apaga nada.
_Avoid_: barra de navegação, abas

**Atalho**:
Tecla do teclado que dispara uma ação do player. Mudo, Tela cheia, Informações, Legendas, Áudio, Modo cinema e Fechar player têm tecla configurável; espaço, Enter, Esc, as setas e Tab são fixos e não podem ser atribuídos. Não dispara enquanto há um campo de texto em foco.
_Avoid_: hotkey, tecla de volume, Setas ocultas

**Pacote de add-on**:
Zip só com dados.
_Avoid_: plugin, extensão com código

**Fonte desconhecida**:
Origem que o usuário adicionou e o app não verificou.
_Avoid_: fonte confiável, loja oficial

**Repositório**:
Endereço que lista add-ons.
_Avoid_: loja de aplicativos

**Fileira**:
Faixa horizontal de pôsteres da tela principal.
_Avoid_: grade, carrossel
