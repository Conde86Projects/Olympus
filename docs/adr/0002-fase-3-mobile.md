# Fase 3: toque no celular

Status: accepted.

O celular já toca para alternar controles, busca com duplo toque, gira o vídeo e abre cheia imersiva; falta fechar o contrato de rotação, cheia e polimento sem inventar gestos. Fase 3 cobre só rotação + tela cheia + polimento do toque existente.

## Decisões assentadas

- Escopo fechado em rotação, tela cheia e polimento (24/10/2026): sem gesto novo; regra do volume (só mudo, sem gesto vertical) continua intocada.
- Rotação travada como está (24/10/2026): fora da cheia o sensor gira livre; a cheia força paisagem, sem cheia em retrato.
- Duplo toque mantido (24/10/2026): metade esquerda volta, direita avança, mesmo passo com flash de 700 ms, sem acumular toques seguidos.
- Cheia só manual (24/10/2026): girar o aparelho não abre cheia sozinha; vale o botão e o `startInFullscreen`.
- Girar-vídeo mantido no Opções (24/10/2026): botões horário/anti-horário, só sessão, sem persistir.
- Toque e auto-hide uniformes (24/10/2026): toque simples alterna os controles com o mesmo `controlsAutoHide` das outras plataformas, sem tempo próprio para o celular.
- Costura MobileChrome única (24/10/2026): um módulo só para imersão/orientação, visibilidade e gestos ("o que o aparelho mostra/esconde em volta do vídeo"), com um único fake de teste; evolui incrementalmente nas fatias F1 → F2 → F3, sem três costuras especulativas.
- Estado dentro do MobileChrome (24/10/2026): visível, cheia e flash pertencem ao módulo; a tela apenas assina, espelhando a fonte única da verdade do `MediaPlayerService` e eliminando o split-brain com o `setState`.
- Assinatura via `Listenable` síncrono (24/10/2026): `ChangeNotifier`/`ValueListenable` consumido com `ListenableBuilder`; valor inicial síncrono garantido, sem `StreamSubscription` na tela nem nos testes.
- Inventário de toque apurado no código (24/10/2026): só tap e duplo toque existem; F3 cobre os dois, nada mais.
- F1 só mobile (24/10/2026): `SystemChrome` apenas; `WindowService` do desktop intocado, só como modelo de costura.

## Considered Options

Galeria de gestos novos (swipe de brilho, seek por arrasto). Rejeitada: ninguém pediu e volume por gesto está cancelado sem volta.

## Consequences

Rotação e cheia ganham regra escrita e testes; o toque atual só é polido onde o smoke apontar atrito; visual intocado.

## Em aberto (costura)

Nenhuma — aceita como Final em 24/10/2026.
