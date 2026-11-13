# Situação atual — Olympus Player

Retrato datado de 01/11/2026 a partir de `docs/` + `lib/` (anterior: 31/10/2026).
Só muda sob comando direto; nunca a cada commit. Atualizado agora por
comando direto do dono, no ticket #28 da spec #16.

Versão publicada: `0.4.2+1014` (tag e release `v0.4.2`). O ciclo da spec #16 saiu na
0.4.0 e a spec #30 (zip, repositório, fileiras) também; correções da auditoria na
0.4.1 e 0.4.2. Há commits na branch `integracao/addons-zip` ainda não publicados
(ver `CHANGELOG.md`, seção "Não lançado"). Tudo abaixo que diz "(PR #29)" ou "não
publicado" é do ciclo da 0.4.0 e já está publicado. Decisões do ciclo:
`docs/adr/0003-acabamento-spec-16.md`; pacote zip só de dados: ADR-0004.
Foco: functions, buttons, pages, pendências gerais.
Glossário canônico em `GLOSSARY.md` (Mudo do app, Mudo do sistema,
Desplugar o mudo, Mutar com o sistema, Trilho, Setas ocultas, Volume inicial, Chrome mobile,
Tamanho do texto, Menu principal, Atalho).

## 1. Pages (rotas reais em `lib/app/routes.dart` + `router.dart`)

Mapa geral (spec 6). Telas recebem só contratos de serviço.

- `/` home — `MobileShell` no celular, `HomeScreen` no desktop/TV.
- `/player` player — `PlayerScreen(item)` (exige `MediaItem`, senão rota desconhecida).
- `/library` biblioteca — `LibraryScreen`.
- `/favorites` favoritos — `FavoritesScreen`.
- `/history` histórico — `HistoryScreen`.
- `/settings` ajustes — `SettingsScreen` + `language_picker_page`.
- `/open` abrir mídia — `OpenMediaScreen` (arquivo local / link HTTP/HTTPS).
- `/onboarding` primeira execução — `OnboardingScreen`.
- `/addons` add-ons — `AddonsScreen`.
- `/addons/details` detalhe do add-on — `AddonDetailsScreen(addonId)`.
- `/addons/catalog` catálogo da fonte — `SourceCatalogScreen(addonId)`.
- `/addons/install` instalar — `AddonInstallScreen`.
- `/addons/repos` repositórios — `AddonReposScreen`.
- `/addons/updates` atualizações — `AddonUpdatesScreen`.
- `/diagnostics` diagnóstico + modo seguro — `DiagnosticsScreen`.

Moldura fora do player: `AppShell` (título + ações + voltar).
Margem lateral 6% presa entre 16 e 96, piso anti-overscan 32 na TV,
largura máxima 1080 centralizada.

Celular (`MobileShell.destinations`, 360 dp):

- Início, Biblioteca, Favoritos, Add-ons, Ajustes. No PR #29, Biblioteca,
  Favoritos e Add-ons podem ser escondidos em Configurações > Menu
  principal; Início e Ajustes ficam sempre. A aba ativa é guardada por
  destino, não por posição.
- Abas montadas sob demanda e mantidas vivas (`_visited`).
- Voltar do sistema fora do Início volta ao Início.
- Detalhe e player abrem por cima das abas.
- `SafeArea` só no mobile (reserva gestos + recorte de câmera).

## 2. Functions (o que o app faz hoje)

### Player (`PlayerScreen` + `MediaPlayerService`)

- Abrir arquivo local e link HTTP/HTTPS compatível.
- Reproduzir / pausar, avançar / retroceder, seek na timeline.
- Retomada da última posição; item concluído (>= 97% assistido) sai do
  "Continuar assistindo", reabre em 0:00 com "Ver de novo".
- Troca de qualidade HLS preserva item/histórico/posição (gate de
  prontidão + no máximo 1 correção validada, senão volta à anterior).
- Seleção de áudio, legendas, velocidade, repetição (painel Opções).
- Tela cheia, modo cinema, modo compacto, sempre no topo (desktop).
- Próximo item (spec 11), ações de erro por tipo de mídia (spec 17).
- Legenda externa (`.srt`, `.vtt`, `.ass`) pelo painel, nas três
  plataformas; legenda ao lado de mesmo nome em vídeo local (celular: só
  se o Android liberar a pasta). Legendas de pastas diferentes com o mesmo
  nome mostram `pasta/nome` no painel (PR #29).
- Atalhos: I/S/A abrem painel direto na subview; ESC fecha painel e
  diálogos; TAB+enter alcança Salvar/Cancelar; setas+OK na TV. No PR #29,
  Mudo, Tela cheia, Informações, Legendas, Áudio, Modo cinema e Fechar
  player têm tecla configurável (padrão M, F, I, S, A, C, Q) em
  Configurações > Atalhos; espaço, Enter, Esc, setas e Tab são fixos.
- Erro de reprodução (PR #29): "Ver informações técnicas" (sem caminho,
  URL completa nem credencial), "Escolher outro vídeo" em arquivo local,
  "Abrir arquivo local" em link sem conexão; falta de acesso aos arquivos
  é um erro de permissão, separado de arquivo ausente.
- Fim do vídeo (PR #29): além de "Ver de novo", botões Biblioteca e Início.
- Celular (PR #29): depois de um seletor do sistema, o vídeo volta a tocar
  só se estava tocando.
- Auto-hide dos controles via `MobileChromeService` (módulo dono do
  estado, tela assina via `ListenableBuilder`).

### Volume (decisão 20/10 + ajuste 21/10, ADR-0001)

Fonte única da regra: `docs/adr/0001-volume-por-plataforma.md`. Resumo:

- Só o Mudo do app dentro do app, em todas as plataformas. Sem Trilho,
  sem +/-, sem gesto vertical.
- Celular/TV: volume sai no aparelho (botões físicos / VOL+/VOL−).
  App não aplica nem salva volume interno no mobile.
- Desktop: volume sai no sistema; `Volume inicial` aplicado na abertura
  e ajustável nas Setas ocultas (passo 0,05, 0,0–1,0), salvo como inicial.
- Mudo do app preserva/restaura o nível anterior.
- Sistema zera ou fica mudo → app muta; sistema sobe → app desmuta (TV e celular, via canal do aparelho).
- VOL+ com app mudado despluga o mudo sem consumir a tecla; VOL− só ajusta o aparelho (não despluga).
- Sistema zerado/mudo reflete no ícone via canal nativo
  (`MainActivity` + `SystemVolumeService`, NoOp fora do Android).

### Biblioteca

- Continuar assistindo, histórico, favoritos, itens locais, progresso.
- Miniaturas locais (`player/thumbnails`, frame ~3 s, JPEG ≤320 px,
  geração ao adicionar + backfill ao reproduzir); pôster remoto com
  fallback; placeholder se falhar. Windows: miniatura tirada pelo
  próprio motor do app (0.3.5); Linux e macOS usam o mesmo caminho, sem teste.
- Arquivos de miniatura são apagados ao remover o item
  (`ThumbnailService.deleteFor`, `test/thumbnail_cleanup_test.dart`).
- Busca pelo título e ordem (recentes, título, duração) lembrada (0.3.4).
- Cartão mostra "Visto hoje", "Visto ontem" ou a data do último acesso,
  igual na Biblioteca, nos Favoritos e em "Continuar assistindo" (PR #29).

### Fontes e add-ons

- Feed remoto compatível + catálogo embutido como fallback.
- Adicionar fonte: URL → validar → prévia manifesto/feed → aviso de
  desconhecida → aprovação explícita → salva desativada → ativar.
- Editar endereço com reaprovação por origem; atualizar catálogo;
  remover sem apagar mídia local.
- Estados: Desconhecida → Aprovada pelo usuário → Verificada.
- Isolamento de falhas por fonte; itens inválidos ignorados um a um.
- Paginação/busca quando suportadas; miniaturas e qualidades opcionais.
- Adaptadores em `lib/services/sources/` (`source_adapter.dart`,
  `demo_source_adapter.dart`, `owned_test_source.dart`).
- Fonte Própria (teste): `https://conde86projects.github.io/olympus-catalog/feed.json`
  (BBB CC-BY 3.0 + HLS multivariante publicado no olympus-catalog).
- Nenhum provider real sem URL + formato + autorização + testes.

### Segurança (SSRF + limites)

- Só HTTP/HTTPS; bloqueia localhost/loopback/privados/link-local/
  multicast/ULA/IPv4-mapped; revalida DNS + cada redirect (max 3).
- Timeout configurável, 256 KB por resposta, 500 itens por feed.
- Credenciais fora do código (`SourceCredentialStore` + secure storage);
  auth só na origem em redirects. Nenhum código executável de feed.

### Diagnóstico / modo seguro

- `DiagnosticsScreen`: tipo do último erro (rede, fonte, decodificador,
  timeout, desconhecido) sem vazar URL/caminho/credencial.
- Contador conservador no desktop; modo seguro manual sempre acessível.
- Versão do app acompanha pubspec. Sem agendamento em 2º plano;
  rollback de 1 nível.

## 3. Buttons (controles visíveis hoje)

### Card `PlayerControls` (desktop/mobile, spec 12.1)

- Linha 1: tempo atual + título central (ellipsis) + duração total.
- `Slider` de progresso em largura total (anula se duração 0).
- Fileira: só Mudo (sem Trilho) + transporte central + engrenagem.
  - `Retroceder 10 segundos`, play/pause, `Avançar 10 segundos`
    (`RoundPlayerButton`).
  - Engrenagem abre `PlayerSettingsPanel` ancorado acima do ícone
    (atalhos I/S/A usam o contexto dela como âncora).
- Cantos: tela cheia no superior esquerdo (fora do card).
- Janela baixa (`dense`, <420 px): 1 fileira só, botões 36, sem título.
- `systemMuted`: ícone reflete também o aparelho.

### `TvPlayerControls` (TV, spec 27)

- Largura limitada, chips áudio/legendas/qualidade com rótulo,
  tokens por classe (720p/1080p/4K), margem anti-overscan.
- D-pad: setas navegam foco; seek/volume por seta só com controles
  ocultos; OK confirma; voltar tem hierarquia (spec 18).
- Qualidade só com HLS multivariante ou `qualities[]`; MP4 único sem
  linha (correto por construção).

### Painel Opções (`PlayerSettingsPanel`, spec 13)

- Submenus internos: Idioma/Áudio, Legendas, Repetição, Qualidade,
  Velocidade, Informações (proveniência: "Arquivo local", add-on...).
- Qualidade: Automática (teto da classe) + Original (se difere) + só
  variantes reais do master; falha volta à Automática.
- Fecha tocando fora, ESC/voltar ou Fechar; não pausa a reprodução;
  faixas tardias aparecem sem reabrir.
- Na TV (PR #29) o painel é um escopo de foco próprio: setas no primeiro e
  no último item não saem dele, em todas as subtelas, e o foco volta ao
  botão de opções ao fechar.
- Em vídeo local sem legenda achada o painel avisa que ela pode ser
  aberta à mão por "Abrir arquivo de legenda…" (PR #29).
- Teto de altura na TV e em tela baixa com rolagem.

### Cantos / modos

- Tela cheia, modo cinema, modo compacto (ícone + tooltip flipam juntos
  no ativo; cinema no mobile mantém saída visível: cantos visíveis
  quando `_mobile && _cinema`, botão "Sair do modo cinema").
- Sempre no topo (desktop, quando suportado).
- Erro supervisionado com "tentar de novo" / "Voltar para Automática".

### Chrome mobile (`MobileChromeService`, ADR-0002)

- Dono do estado: cheia (imersão + paisagem via `SystemChrome`),
  visibilidade + auto-hide (`AppConstants.controlsAutoHide`),
  flash de duplo toque (`±10 s`, 700 ms, `seekFlashLeft`).
- `show/hide/toggle/poke/cancel` + `autoHideGuard` (painel/overlay
  seguram o hide) + `onControlsAutoHidden` (foco da tela).
- Fake com `advanceTime` determinístico (sem espera real).
- Toque simples alterna visibilidade (precisa bombear `kDoubleTapTimeout`);
  duplo toque = seek ±10 s + flash.

## 4. Pendências gerais (backlog)

Controle por pendências, sem divisão por entrega. Conferido em 01/11/2026
contra `lib/`, `test/`, `git tag` e `gh issue`.

### Feito (publicado até a v0.3.5)

- Estilo visual de legendas: tamanho, cor, posição e fundo em Ajustes, desenhados
  pelo Flutter acima da barra de controles (0.3.0; `sub-*` do mpv não foi o caminho).
  Falta só conferir essa versão no Windows (nota de 31/10 no BACKLOG).
- Miniaturas órfãs apagadas ao remover itens (`test/thumbnail_cleanup_test.dart`).
- Item concluído reabre em 0:00 com "Ver de novo" (`test/completed_replay_test.dart`).
- `startInFullscreen` no celular: aplicado depois do primeiro quadro
  (`test/mobile_chrome_test.dart`).
- Stall de rede: buffering acima de `bufferTimeout` (15 s) vira erro de tempo
  esgotado com "tentar de novo", e o mpv recebe `network-timeout` do mesmo valor.
  Falta conferir no aparelho com rede lenta.
- Vídeo local pelo caminho digitado na TCL: ticket #15 fechado como não
  reproduzido na v0.3.4 (item ficou na Biblioteca nos dois casos testados).
- Detecção fria de variantes HLS: resolvida em 31/10 (`3a80efb`, BACKLOG).
- Diálogos e botões na TV (31/10): foco com borda e fundo tintado, Cancelar
  focado em "Remover da biblioteca". Validado na TCL e no Windows. Validado na
  TCL em 31/10: o vídeo de teste chegou ao fim, o diálogo "Reprodução concluída"
  respondeu ao controle e "Fechar" saiu do player. Mudo validado no Windows.
- Legenda externa, legenda ao lado, busca e ordem da Biblioteca, logo e
  miniatura no Windows: v0.3.2 a v0.3.5 (`CHANGELOG.md`).

### Feito no ciclo da spec #16 (PR #29, não publicado)

- Tamanho do texto (Normal, Grande, Maior); data do último acesso no cartão.
- Erros com informações técnicas, "Escolher outro vídeo" e "Abrir arquivo local";
  permissão de arquivos separada de arquivo ausente.
- Fim do vídeo com Biblioteca e Início; painel de opções com foco na TV.
- Menu principal escolhido pelo usuário; atalhos configuráveis.
- Celular retoma o play depois de um seletor do sistema; legendas homônimas;
  aviso de legenda ao lado não encontrada.
- Conferido em 01/11/2026 na TCL: data do cartão, fim do vídeo com Biblioteca e
  Início, menu principal (desligar e ligar Add-ons) e foco do painel de opções.
  Conferido no emulador: tamanho do texto, erro de permissão (incluindo "Tentar
  novamente" pedindo a permissão), informações técnicas e aviso de legenda ao lado.
  Falta conferir no Windows: atalhos configuráveis, tamanho do texto e a legenda
  ao lado em `.vtt` e `.ass`; e a legenda de mesmo nome em pastas diferentes, que
  só tem teste automático.

### Em aberto

- Tizen fora (sem alvo Flutter oficial).
- AVD-TV com EGL quebrado (decode/relógio OK, frame preto); validação em TV
  física de outro modelo (Google TV, Fire TV, Mi Box) e em outro celular.
- compileSdk fixo em 36 por causa do file_picker.
- hwdec por software no PC de dev (suficiente p/ 1080p30; 4K a avaliar).
- Fonte real: nenhum provider real sem URL + formato + autorização + testes;
  GitHub Issues é o tracker; sem commit/push/tag sem pedido explícito.
- Assinatura de pacotes, checagem de updates em segundo plano e miniaturas
  mais avançadas: futuro, sem escopo definido.
- Qualidade na TV só aparece com HLS multivariante ou `qualities[]`;
  MP4 único corretamente sem linha.
- Flash branco no primeiro `screencap` da TV após reinstalar: cosmético.
- Crash nativo no FinalizerDaemon (`SurfaceTexture.release`, SIGSEGV
  0x424) em ciclos de abre/sai: LIMITAÇÃO CONHECIDA E CONGELADA,
  exclusiva do hardware da TCL (Android 9/Realtek, mediacodec_embed)
  com a media_kit_video 1.3.1 (sem `dispose()` no `VideoController`).
  Mitigações no app: `stop()` na saída do player + backstop do
  `IntentReceiver` no `onDestroy` (sem vazamento mesmo em queda
  abrupta). Desktop/celular nunca reproduziram.
