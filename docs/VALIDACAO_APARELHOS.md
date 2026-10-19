# Validação em vários aparelhos (vídeo e tela)

Objetivo: o Olympus tem de rodar leve e se adaptar a qualquer TV,
TV box, celular e janela do Windows. A TCL 50" (Realtek + Mali-470,
Android 9) é o aparelho mais fraco que temos e serve de piso; este
roteiro cobre o que muda de aparelho para aparelho.

## Como o vídeo funciona no Android (18/10/2026)

| Camada | O que faz | Quando entra |
|---|---|---|
| Saída direta (`mediacodec_embed`) | O decodificador de hardware desenha direto na tela. Leve: 1080p a 1x na TCL. | Padrão no Android |
| Fallback por arquivo | Formato sem hardware (Theora, VC-1, MJPEG, HEVC 10-bit em TV fraca) cai no modo compatível só naquele arquivo. | Automático (erro `HW uploader` do mpv) |
| Guarda por aparelho | 2 quedas nativas seguidas durante o vídeo com saída direta ligam o modo compatível de vez naquele aparelho. | Automático (`VideoOutputGuard`) |
| Modo de vídeo compatível | Configurações → Reprodução. O usuário força o caminho antigo (`vo=gpu`). Desligar zera a guarda. | Manual; vale ao reabrir o app |

Desktop (Windows/Linux) não usa nada disso: segue no padrão do
media_kit.

## Aparelhos alvo (mínimo antes de uma versão)

- [x] TCL 50" v8-r851t02-lf1v660 — Realtek, Mali-470, Android 9 (piso).
- [ ] Google TV / Chromecast com Google TV — Amlogic.
- [ ] Fire TV Stick ou Mi Box — MediaTek / Amlogic.
- [ ] Celular Android recente (qualquer).
- [x] Windows: janela grande, janela pequena/minimizada, sempre no topo
  (18/10/2026, ver `VALIDACAO_WINDOWS.md`).

Registrar em cada um: modelo, chip (`getprop ro.board.platform` /
`ro.hardware`), Android, `wm size` e `wm density`.

## Vídeo (por aparelho Android)

Medir velocidade como na TCL: reproduzir ~60 s, voltar, e comparar
`positionMs` do `history.json` com o tempo de relógio (alvo ≥ 0,95x).
Ver o `VO:` no logcat (build debug, `[player-diag]`).

| Caso | Esperado | Resultado |
|---|---|---|
| H.264 1080p30 (MP4) | 1x, `VO: [mediacodec_embed]` | |
| H.264 1080p60 | 1x ou queda de quadros sem travar | |
| HLS master (Mux x36xhzz) | abre, teto de qualidade da TV, retomada | |
| HEVC 1080p 8-bit | 1x direto | |
| HEVC 4K 10-bit / HDR | direto, ou fallback com imagem (nunca tela preta) | |
| VP9 1080p (WebM) | direto ou fallback com imagem | |
| AV1 1080p | direto (aparelho novo) ou fallback com imagem | |
| MPEG-2 entrelaçado (gravação de TV) | imagem sem "pente" forte; anotar | |
| Theora / VC-1 (formato sem hardware) | fallback com imagem e áudio | |
| Próximo vídeo após um fallback | volta para `mediacodec_embed` | |
| Legenda externa `.srt` | aparece por cima do vídeo | |
| Legenda embutida (MKV) | aparece; troca no painel | |
| Troca de áudio (MKV multi-áudio) | troca sem parar o vídeo | |
| Girar | imagem gira | |
| Seek ±10 s, pausa, retomada | posição exata | |
| Home do controle no meio do vídeo e voltar | sem contar como queda | |
| Modo de vídeo compatível ligado + reabrir | `VO: [gpu]` | |

## Tela (todas as plataformas)

| Caso | Esperado | Resultado |
|---|---|---|
| TV 720p (`wm size 1280x720`) | layout compacto, nada cortado | |
| TV 1080p a 320 dpi (960x540 lógico) | menus compactos aprovados | |
| TV 4K (`wm size 3840x2160`) | tokens "grande", nada minúsculo | |
| Overscan | nada encostado na borda | |
| Celular retrato e paisagem | sem estouro | |
| Windows 1920x1080 maximizado | layout desktop | OK 18/10 em janela de 1920x1080 lógicos (o monitor daqui é ultrawide; maximizado nele está na linha ultrawide): card de 880, título e volume, igual ao anterior |
| Windows janela pequena (~480x270) e modo compacto | controles legíveis, sem estouro | OK 18/10 após correção: card de uma fileira (botões 36, tempo 12) abaixo de 420 de altura; menus rolam; mínimo da janela 480x270 (era 800x600 e prendia o compacto) |
| Windows sempre no topo + minimizar/restaurar | vídeo continua, posição salva | OK 18/10 após correção: minimizar grava a posição (1:16), vídeo seguiu (1:27 ao restaurar), topo mantido; sair do compacto volta ao tamanho e ao topo da preferência |
| Windows ultrawide | conteúdo centralizado | OK 18/10 (3440x1440 a 125%): menus em 1080 centralizados, vídeo com barras laterais, card centralizado |

`wm size reset` ao terminar os testes de resolução simulada.

## Arquivos de teste

Preferir streams públicos de teste (sem baixar filmes grandes no PC):
`test-videos.co.uk` (Bunny H.264/HEVC/VP9/AV1 em 10 s), Mux
`x36xhzz` (HLS com variantes 240p–1080p). Formatos raros podem ser
gerados no PC com o ffmpeg (alguns MB) e enviados com `adb push`.
