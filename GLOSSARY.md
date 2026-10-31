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
