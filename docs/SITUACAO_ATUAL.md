# Situação atual — Olympus Player

Retrato datado de 31/10/2026 a partir de `docs/` + `lib/`.
Só muda sob comando direto; nunca a cada commit.
Foco: functions, buttons, pages, pendências gerais.
Glossário canônico em `GLOSSARY.md` (Mudo do app, Mudo do sistema,
Desplugar o mudo, Trilho, Setas ocultas, Volume inicial, Chrome mobile).

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

- Início, Biblioteca, Favoritos, Add-ons, Ajustes.
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
- Atalhos: I/S/A abrem painel direto na subview; ESC fecha painel e
  diálogos; TAB+enter alcança Salvar/Cancelar; setas+OK na TV.
- Auto-hide dos controles via `MobileChromeService` (módulo dono do
  estado, tela assina via `ListenableBuilder`).

### Volume (decisão 20/10 + ajuste 21/10, ADR-0001)

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
  fallback; placeholder se falhar. Desktop sem geração (MissingPlugin).
- Órfãos não apagados ao remover (limitação conhecida).

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

Controle por pendências, sem divisão por entrega.

- Estilo visual de legendas: tamanho, cor, fundo e posição
  (`sub-*` via `NativePlayer.setProperty` a reavaliar).
- Miniaturas órfãs não apagadas ao remover itens.
- Item concluído reabre em 0:00 com "Ver de novo" (sair sem assistir
  preserva o concluído; a concluir some do "Continuar assistindo").
- Stall de rede vira "Cancelar" eterno: falta timeout visível no mpv +
  overlay com "tentar de novo".
- Tizen fora (sem alvo Flutter oficial).
- AVD-TV com EGL quebrado (decode/relógio OK, frame preto).
- compileSdk fixo em 36 por causa do file_picker.
- hwdec por software no PC de dev (suficiente p/ 1080p30; 4K a avaliar).
- `startInFullscreen` no mobile segue lacuna conhecida.
- Qualidade na TV só aparece com HLS multivariante ou `qualities[]`;
  MP4 único corretamente sem linha.
- Nenhum provider real sem URL + formato + autorização + testes;
  GitHub Issues é o tracker; sem commit/push/tag sem pedido explícito.
- Vídeo local aberto pelo caminho digitado toca mas não fixa na
  biblioteca (reproduzido 2× na TCL em 31/10, sem queda no meio;
  causa aberta, correção futura).
- Diálogos e botões na TV (31/10): o foco ficava azul parado no botão
  errado e o "Cancelar" aparecia como selecionado. Corrigido no
  `FocusableButton`: foco com borda de 2 px e fundo tintado, ação
  principal preenchida só quando focada, ação destrutiva em vermelho
  quando focada. Diálogo "Remover da biblioteca" com Cancelar focado
  por padrão. Validado na TCL (erro com arquivo ausente: setas movem o
  foco, OK em Cancelar fecha sem remover) e no Windows (setas, Esc,
  painel de opções com o vídeo tocando). Pendente: o diálogo de fim de
  reprodução na TCL, que exige o vídeo chegar ao fim no aparelho.
- Crash nativo no FinalizerDaemon (`SurfaceTexture.release`, SIGSEGV
  0x424) em ciclos de abre/sai: LIMITAÇÃO CONHECIDA E CONGELADA,
  exclusiva do hardware da TCL (Android 9/Realtek, mediacodec_embed)
  com a media_kit_video 1.3.1 (sem `dispose()` no `VideoController`).
  Mitigações no app: `stop()` na saída do player + backstop do
  `IntentReceiver` no `onDestroy` (sem vazamento mesmo em queda
  abrupta). Desktop/celular nunca reproduziram.
