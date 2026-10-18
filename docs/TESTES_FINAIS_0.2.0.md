# Pacote de testes finais — próximo marco (0.2.0, sem tag)

Roteiro dos testes manuais que fecham a fase. Preparado em
18/10/2026, depois da verificação técnica mobile (625/625 testes,
`dart analyze` limpo, emulador de celular e de TV, Windows).

Regras desta rodada:

- **Sem tag** do próximo marco até validar em um **celular físico**.
  `v0.1.0` (`bd3270a`) e as tags `rc` anteriores ficam intactas.
- **Sem baixar vídeos grandes** (Sintel, Tears of Steel, Big Buck
  Bunny completos). A mídia de teste segue sendo o `mux-smoke`.
- O `mux-smoke` é **temporário**: só sai quando o feed definitivo
  (mídia própria/licenciada) for publicado. Ver
  `docs/FONTE_PROPRIA_TESTE.md`.
- Volume visual no celular **não bloqueia** (backlog: "Mobile:
  controle visual de volume ou gesto vertical"). Mudo + botões
  físicos são aceitos.

## Gates antes de começar

- [ ] Árvore limpa no commit testado; anotar o hash aqui: `______`.
- [ ] `flutter test` verde (anotar total: `___`).
- [ ] `dart analyze` limpo.
- [ ] Versão nas 4 fontes conferida (pubspec, `AppConstants`,
      Diagnóstico, Sobre) — o bump para 0.2.0 só no commit do marco.
- [ ] Feed temporário respondendo:
      `https://8080-i3z7luqmkzuzszqjs7uy1-59e363bb.us4.manus.computer/feed.json`
      (1 item, `mux-smoke`, "Teste HLS — Mux x36xhzz").
- [ ] APK gerado (`flutter build apk`) e SHA-256 anotado:
      `______`.
- [ ] Instalar **sempre** com o serial explícito
      (`adb -s <serial> install -r ...`): a TCL fica conectada por
      Wi-Fi (`192.168.1.4:5555`) e não pode receber o APK errado.

## Como registrar evidência

- Android: `adb -s <serial> logcat -s flutter` e filtrar
  `[player-diag]` (motor, `VO:`, `pause`, `seek`, `volume`) e
  `[hls-resume]` (retomada HLS: `targetMs`, pouso).
- Histórico: `history.json` (posição salva, `completed`).
  Android: `adb -s <serial> shell run-as com.example.player cat
  files/player_data/history.json` (build debug);
  Windows: `%APPDATA%\com.example\player\player_data\history.json`.
- Diagnóstico → **Exportar relatório** ao fim de cada aparelho.
- Anotar o resultado em cada caixa: `OK`, `FALHA (o que houve)` ou
  `N/A`.

## 1. Celular físico (Android, toque)

Registrar: modelo, Android, chip (`getprop ro.board.platform`),
`wm size`, `wm density`.

Composição mobile (só com o modo TV desligado; o automático deixa
desligado em celular):

- [ ] Retrato: Início, abas e player sem estouro nem corte.
- [ ] Paisagem: idem; player com controles em uma fileira.
- [ ] Toque mínimo de 48 dp: abas, cantos do player, botões do card.
- [ ] Navegação inferior: Início, Biblioteca, Favoritos, Add-ons,
      Ajustes; a aba mantém o estado ao trocar; o voltar do sistema
      fora do Início volta ao Início; no Início sai do app.
- [ ] Nenhuma seta de voltar nas abas (inclusive logo após a
      apresentação inicial).
- [ ] Telas abertas por cima das abas (instalar add-on, detalhes,
      catálogo) com o fim do conteúdo **acima** da barra de gestos.
- [ ] Catálogo: Add-ons → Instalar → Link → URL do feed → revisar →
      marcar o aceite → Instalar (entra desativado) → Ativar → Abrir
      catálogo → `mux-smoke` → Reproduzir.
- [ ] Reprodução: imagem e som; `VO:` no log.
- [ ] Toque no vídeo alterna os controles; toque duplo à esquerda
      volta 10 s e à direita avança 10 s, com o rótulo "-10 s"/"+10 s".
- [ ] Pausa e play (`pause=true/false` no log).
- [ ] Seek pelos botões ±10 s e arrastando a barra.
- [ ] Mudo liga/desliga (`volume=0` / `volume=100`); botões físicos
      de volume funcionam.
- [ ] Tela cheia: gira para paisagem e esconde as barras do sistema;
      sair devolve as barras e a orientação livre.
- [ ] Voltar do sistema no player: sai e grava a posição ("parou em
      m:ss" no Início).
- [ ] Retomada: reabrir pelo Início volta ao ponto salvo
      (`[hls-resume]` com `targetMs` e pouso dentro da tolerância).
- [ ] Botão Home no meio do vídeo e voltar ao app: posição gravada,
      sem tela preta.
- [ ] Modo seguro: Ajustes → Diagnóstico → **Ativar modo seguro** →
      reabrir o app → faixa de modo seguro no Início, add-ons não
      carregados → desativar → reabrir → add-ons de volta.
- [ ] Diagnóstico: abre, mostra versão/aparelho, **Exportar
      relatório** funciona.

## 2. Windows

Ver também `docs/VALIDACAO_WINDOWS.md` (já validado em 125% e 150%
em 18/10/2026; repetir só o que mudou desde então).

- [ ] Janela pequena (480x270, mínimo): card de uma fileira,
      menus rolam, sem faixas amarelas/pretas.
- [ ] Janela grande / maximizada: desenho de desktop (card 880).
- [ ] Catálogo: instalar o feed, ativar, abrir, reproduzir `mux-smoke`.
- [ ] HLS: abre, imagem e som.
- [ ] Qualidade: Configurações do player → Qualidade → trocar para
      uma variante e voltar para Automática; posição preservada.
- [ ] Retomada: fechar o player e reabrir no ponto salvo.
- [ ] Histórico: item aparece com posição; remover do histórico pede
      confirmação.
- [ ] Erro controlado: link inválido ou rede desligada → mensagem de
      erro com Tentar novamente / Editar link / Fechar (nunca tela
      vermelha nem trava).
- [ ] Compacto + sempre no topo + minimizar/restaurar: vídeo segue,
      posição gravada ao minimizar.
- [ ] Fechar pelo X do Windows com vídeo tocando: posição gravada.

## 3. TCL (BeyondTV, Android 9, D-pad)

- [ ] D-pad em todas as telas (Início, Add-ons, catálogo, player,
      Configurações); foco sempre visível; BACK volta um nível.
- [ ] Catálogo pelo controle remoto até reproduzir o `mux-smoke`.
- [ ] HLS: 1x, `VO: [mediacodec_embed]`.
- [ ] Qualidade automática: teto da TV respeitado; observador sem
      downgrade em rede boa.
- [ ] Qualidade manual: trocar variante e voltar; posição preservada
      (ver BACKLOG, seek pós-troca).
- [ ] Retomada: sair e reabrir no ponto salvo.
- [ ] Rede fria: desligar a rede, abrir o item, religar → erro
      controlado e recuperação com Tentar novamente; retomada fria
      dentro da tolerância.
- [ ] Histórico: posição e "Continuar assistindo" corretos.
- [ ] Fonte fora do ar: Editar endereço do add-on para um host
      inexistente (ou feed desligado) → Atualizar catálogo mostra
      erro legível e o app segue usável (anotar o que acontece com
      o catálogo já carregado).
- [ ] Layout da TV intacto (menus compactos aprovados, cantos de 36,
      agora com fundo escuro sobre vídeo claro).

## 4. Comuns (rodar em pelo menos um aparelho de cada tipo)

- [ ] Fontes: instalar, ativar/desativar, editar endereço (pede
      reaprovação), atualizar catálogo, remover.
- [ ] Catálogo: busca local filtra; item mostra título, descrição e
      duração; Reproduzir abre o player.
- [ ] Player: legenda/áudio no painel (se a mídia tiver), velocidade,
      informações.
- [ ] Conclusão em 97%: avançar até ≥ 97% da duração e sair → item
      marcado concluído e fora do "Continuar assistindo".
- [ ] "Ver de novo": reabrir um item concluído → começa do início e
      mostra a oferta "Ver de novo"; usar, fechar e sair sem assistir
      preservam o histórico concluído.
- [ ] Modo seguro automático: 2 quedas seguidas no arranque ativam o
      modo seguro (só se for possível provocar sem risco; senão `N/A`
      e cobrir pelo manual).
- [ ] Diagnóstico: relatório exportado em cada aparelho.
- [ ] Erro de rede: link indisponível e sem rede, com as ações certas
      por tipo de mídia.

## Fechamento

- [ ] Todas as caixas com resultado; falhas viram itens no
      `docs/BACKLOG.md` (bloqueante ou não).
- [ ] Publicar o feed definitivo e trocar o `mux-smoke` por mídia
      própria/licenciada (passo 6–7 da ordem combinada).
- [ ] Repetir o smoke curto com o feed definitivo.
- [ ] Só então: bump para 0.2.0, checklist de release e tag.
