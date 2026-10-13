# Changelog

Histórico de versões do player, escrito para humanos (o que mudou e
se importa). Detalhes de implementação ficam nos documentos em
`docs/`.

## [Não lançado]

## [0.1.0-rc.2] - 2026-10-13

Segundo release candidate: qualidade dinâmica e retomada HLS na
TV, aprovadas em hardware real (TCL). Gates preservados: suíte
completa verde e `dart analyze` limpo.

### Adicionado

- Diagnóstico identifica o tipo do último erro (rede, fonte,
  decodificador, tempo esgotado, desconhecido) na tela e no
  relatório exportado — sem vazar mensagem, caminho, URL ou
  credencial.
- Versão do app no diagnóstico acompanha o pubspec.
- Interface adaptativa para TV (spec 27): composição própria do
  player (largura limitada, chips de áudio/legendas/qualidade com
  rótulo), tokens por classe de largura (720p/1080p/4K), margem
  segura anti-overscan e breakpoints validáveis em hardware real.
  Windows inalterado.
- Seleção manual de qualidade HLS na TV (Opções → Qualidade, por
  D-pad): Automática (padrão, com o teto da classe), Original e
  só as variantes reais do master; a troca preserva item,
  histórico e posição, e a falha de variante volta para a
  Automática sem texto técnico.
- Política automática por desempenho: perfil por
  plataforma/Leanback/viewport (TV compacta/normal com o teto que
  estabilizou a TCL; TV 4K e desktop sem teto) e, na TV em
  Automática, um degrau abaixo uma única vez se a reprodução
  ficar lenta no início. Override manual nunca é rebaixado e a
  qualidade efetiva aparece no painel.
- Retomada HLS precisa: o seek inicial aguarda prontidão real
  (saída de buffering + primeiro avanço de posição, com timeout
  limitado) e o pouso é validado — no máximo uma correção, sem
  loops. Pouso incorreto pausa com segurança e preserva o
  histórico do ponto errado, com o motivo no log técnico.

### Corrigido

- Retomada HLS na TCL caía segundos ou minutos longe do ponto
  salvo (seek em demuxer frio descartado em silêncio + correção
  cega): agora pousa exato no alvo em hardware real, sem mexer
  em MP4, playlists simples, histórico ou IDs.

## [0.1.0-rc.1] - 2026-10-12

Primeiro release candidate: player local completo, desktop, TV e
fontes por dados (sem provider real conectado).

### Adicionado

- Reprodução local (media_kit/libmpv): arquivo, link autorizado,
  pausa/retomada, busca, volume, velocidade, faixas de áudio e
  legendas, tela cheia e modo compacto.
- Card de controles flutuante fosco (Showtime): tempo/título/
  duração, progresso total e fileira de botões; tela cheia no
  canto superior esquerdo e ações+fechar à direita.
- Biblioteca, histórico e favoritos persistentes, com ponto de
  retomada exato e "parou em" nos cartões.
- Desktop Windows/Linux: janela redimensionável, ultrawide, modo
  escuro Adwaita minimalista, atalhos de teclado (I/S/A, C, ESC).
- TV/Android: Leanback com banner, navegação por D-pad, foco
  visível, botão voltar preservando a posição.
- Fontes por dados: catálogo embutido, feed remoto por URL,
  adaptador demo realista, pôster e qualidades dinâmicas quando a
  fonte informa.
- Gerência de fontes: adicionar por URL com prévia, aviso de fonte
  desconhecida, aprovação explícita, início desativado, ativar,
  editar (nova aprovação se a origem mudar), atualizar e remover.
- Diagnóstico e modo seguro: inicia sem fontes externas, exporta
  logs sem credenciais, identifica o último erro.

### Segurança

- Fontes desconhecidas: somente dados compatíveis, nenhum código
  executável ("dados sim, código nunca").
- HTTP/HTTPS apenas, timeout, 256 KB por resposta, 500 itens por
  feed, isolamento de falhas por fonte.
- Barreira SSRF: bloqueia localhost, loopback, redes privadas,
  link-local, multicast, ULA e IPv4 mapeado; revalida todos os
  endereços do DNS e cada redirect (máx. 3); autenticação só na
  origem.
- Credenciais em armazenamento seguro do SO
  (`flutter_secure_storage`), nunca no código ou nos logs.

### Corrigido

- Retomada a frio caindo no início (leitura de duração do motor com
  retentativas espaçadas).
- Slider capturando o OK no D-pad (ação dedicada de saída).
- Links sempre offline no Android (faltava permissão INTERNET).
- Amostra de teste com 403 trocada por HLS público estável.
- Rótulo "Qualidade" atualiza ao vivo no diálogo aberto.

### Limitações conhecidas

- Estilo visual das legendas (tamanho/cor/fundo/posição): o
  media_kit não expõe as propriedades do mpv pela API Dart.
- Pixel-perfeito em TV antiga (Mali-470 não renderiza
  Vulkan/GLES3); validação visual vale para TVs atuais.
- Nenhum provider real conectado: a primeira fonte autorizada
  entrará como adaptador isolado em `lib/services/sources/`.

Verificação: 396/396 testes passando, `flutter analyze` limpo.
